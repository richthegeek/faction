module.exports = (server) ->
	# list all fact hooks for this fact-type
	server.get '/facts/:fact-type/hooks', Hook_Model.route, (req, res, next) ->
		console.log req.params.asQuery()
		req.model.loadPaginated req.params.asQuery(), req, ErrorHandler next, (err, response) ->
			res.send response

	# update a hook for this fact-type
	server.post '/facts/:fact-type/hooks/:hook-id', Hook_Model.route, (req, res, next) ->
		# insert a hook config.
		# insert an opstream for turning configs into opstreams.
		delete req.body._id
		req.body.fact_type = req.params['fact-type']
		req.body.hook_id = req.params['hook-id']

		req.model.update req.params.asQuery(), req.body, ErrorHandler next, (err, updated) =>
			res.send {
				status: 'ok',
				statusText: 'The hook was ' + (updated and 'updated.' or 'created.'),
				hook: req.model.export()
			}

	# delete a hook for this fact-type
	server.del '/facts/:fact-type/hooks/:hook-id', Hook_Model.route, (req, res, next) ->
		# delete the config, the opstream should take care of the rest.
		req.model.remove req.params.asQuery(), (err, count) ->
			res.send {
				status: 'ok',
				statusText: 'The hook was deleted.',
				deleted: count | 0
			}
