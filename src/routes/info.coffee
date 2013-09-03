module.exports = (server) ->

	# post information of a specific type
	server.post '/info/:info-type', Info_Model.route, (req, res, next) ->
		req.model.create req.params['info-type'], req.body, (err) ->
			if err then throw err

			res.send {
				status: 'ok',
				statusText: 'Information recieved'
			}

	# list all info handlers for this info-type
	server.get '/info/:info-type/handlers', Infohandler_Model.route, (req, res, next) ->
		type = req.params['info-type']
		req.model.loadPaginated {info_type: type}, req, (err, response) ->
			if err then throw err
			res.send response

	# update a handler for this info-type
	server.post '/info/:info-type/handler/:handler-id', Infohandler_Model.route, (req, res, next) ->
		# insert a handler config.
		# insert an opstream for turning configs into opstreams.
		req.body.handler_id = req.params['handler-id']
		req.model.create req.params['info-type'], req.body, (err) =>
			if err then throw err
			res.send {
				status: 'ok',
				statusText: 'The information handler was updated.',
				handler: @export()
			}

	# delete a handler for this info-type
	server.del '/info/:info-type/handler/:handler-id', Infohandler_Model.route, (req, res, next) ->
		# delete the config, the opstream should take care of the rest.
		req.model.remove {_id: req.params['handler-id']}, (err, count) ->
			res.send {
				status: 'ok',
				statusText: 'The information handler was deleted.',
				deleted: count | 0
			}
