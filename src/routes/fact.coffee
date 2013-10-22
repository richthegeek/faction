async = require 'async'
module.exports = (server) ->

	# list all known fact types
	server.get '/facts', (req, res, next) ->
		Fact_Model.getTypes req.account, ErrorHandler next, (err, types) ->
			types.detailed ErrorHandler next, (err, info) ->
				res.send info

	# retrieve all facts of this type, paginated.
	server.get '/facts/:fact-type', Fact_Model.route, (req, res, next) ->
		req.model.loadPaginated req.body, req, ErrorHandler next, (err, response) ->
			res.send response

	# get fact settings
	server.get '/facts/:fact-type/settings', Factsettings_Model.route, (req, res, next) ->
		req.model.load {_id: req.params['fact-type']}, ErrorHandler next, (err, found) ->
			res.send @export()

	# update fact settings
	server.post '/facts/:fact-type/settings', Factsettings_Model.route, (req, res, next) ->
		req.body._id = req.params['fact-type']
		req.model.update {_id: req.body._id}, req.body, ErrorHandler next, (err, update) ->
			res.send {
				status: 'ok',
				statusText: 'The fact settings were updated.'
				settings: @export()
			}


	# retrieve a specific fact by ID
	server.get '/facts/:fact-type/fact/:fact-id', Fact_Model.route, (req, res, next) ->
		req.model.load {_id: req.params['fact-id']}, true, ErrorHandler next, () ->
			@updateFields () ->
				res.send @export()

	# retrieve a specific fact by ID
	server.get '/facts/:fact-type/fact_def/:fact-id', Fact_deferred_Model.route, (req, res, next) ->
		req.body.with ?= []
		req.body.path ?= 'this'

		req.body.with = [].concat.call [], req.body.with

		if 'this' isnt req.body.path.substring 0, 4
			req.body.path = 'this.' + req.body.path

		req.model.load {_id: req.params['fact-id']}, true, ErrorHandler next, (err, found) ->
			if err or not found
				return res.notFound 'fact'
			async.map req.body.with, @data.get.bind(@data), () =>
				@data.eval req.body.path, (err, result) =>
					res.send result

	# update a fact by ID.
	server.post '/facts/:fact-type/fact/:fact-id', Fact_Model.route, (req, res, next) ->
		req.body._id = req.params['fact-id']
		req.model.update {_id: req.body._id}, req.body, ErrorHandler next, (err, updated) ->
			res.send {
				status: 'ok',
				statusText: 'The fact was ' + (updated and 'updated.' or 'created.'),
				fact: @export()
			}

	# delete all facts of a specific type
	server.del '/facts/:fact-type', Fact_Model.route, (req, res, next) ->
		req.model.removeFull ErrorHandler next, () ->
			res.send {
				status: 'ok',
				statusText: 'All facts of this type have been deleted.'
			}

	# delete a specific fact by ID
	server.del '/facts/:fact-type/fact/:fact-id', Fact_Model.route, (req, res, next) ->
		req.model.remove {_id: req.params['fact-id']}, ErrorHandler next, (err, count) ->
			res.send {
				status: 'ok',
				statusText: 'The fact was deleted.',
				deleted: count | 0
			}
