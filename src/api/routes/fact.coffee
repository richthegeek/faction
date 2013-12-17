async = require 'async'
module.exports = (server) ->

	# temporary override
	Fact_Model = Fact_deferred_Model

	# list all known fact types
	server.get '/facts', (req, res, next) ->
		Fact_Model.getTypes req.account, ErrorHandler next, (err, types) ->
			types.detailed ErrorHandler next, (err, info) ->
				res.send info

	# retrieve all facts of this type, paginated.
	server.get '/facts/:fact-type', Fact_Model.route, (req, res, next) ->
		req.body ?= {}
		req.body.query ?= {}
		req.body.map ?= {}

		req.model.loadPaginated req.body.query, req, ErrorHandler next, (err, response) ->
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
			res.send @export()

	# retrieve a specific fact by ID
	server.get '/facts/:fact-type/fact_def/:fact-id', Fact_Model.route, (req, res, next) ->
		req.model.load {_id: req.params['fact-id']}, true, ErrorHandler next, (err, found) ->
			if err or not found
				return res.notFound 'fact'

			@withMap req.body.with, req.body.map, (err, result) =>
				next res.send result


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

	# mark a fact as updated...
	server.post '/facts/:fact-type/update/:fact-id', Fact_Model.route, (req, res, next) ->
		req.model.load {_id: req.params['fact-id']}, true, ErrorHandler next, (err, found) ->
			console.log 'update', err, found

			return next res.notFound 'user' if not found
			@markUpdated () =>
				next res.send {
					status: "ok",
					statusText: "This fact has been marked as updated.",
					fact: @export()
				}

	server.post '/facts/:fact-type/update', Fact_Model.route, (req, res, next) ->
		req.model.markUpdatedFull ErrorHandler next, (err, ids) ->
			console.log 'updated', err, ids
			next res.send {
				status: "ok",
				statusText: "All facts of this type have been marked as updated."
			}
