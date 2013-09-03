module.exports = (server) ->

	# list all known fact types
	server.get '/facts', (req, res, next) ->
		Fact_Model.getTypes req.account, (types) ->
			types.detailed (info) ->
				res.send info

	# retrieve all facts of this type, paginated.
	server.get '/facts/:fact-type', Fact_Model.route, (req, res, next) ->
		req.model.loadPaginated req.body, req, (err, response) ->
			if err then throw err
			res.send response

	# retrieve a specific fact by ID
	server.get '/facts/:fact-type/:fact-id', Fact_Model.route, (req, res, next) ->
		req.model.load {_id: req.params['fact-id']}, () ->
			res.send @export()

	# update a fact by ID.
	server.post '/facts/:fact-type/:fact-id', Fact_Model.route, (req, res, next) ->
		req.body._id = req.params['fact-id']
		req.model.update {_id: req.params['fact-id']}, req.body, (err, updated) ->
			res.send {
				status: 'ok',
				statusText: 'The fact was ' + (updated and 'updated.' or 'created.'),
				fact: @export()
			}

	# delete all facts of a specific type
	server.del '/facts/:fact-type', Fact_Model.route, (req, res, next) ->
		req.model.removeFull () ->
			res.send {
				status: 'ok',
				statusText: 'All facts of this type have been deleted.'
			}

	# delete a specific fact by ID
	server.del '/facts/:fact-type/:fact-id', Fact_Model.route, (req, res, next) ->
		req.model.remove {_id: req.params['fact-id']}, (err, count) ->
			res.send {
				status: 'ok',
				statusText: 'The fact was deleted.',
				deleted: count | 0
			}
