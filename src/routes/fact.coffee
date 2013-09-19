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
		req.model.load {_id: req.params['fact-id']}, ErrorHandler next, () ->
			res.send @export()

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
