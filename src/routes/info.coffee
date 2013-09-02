module.exports = (server) ->

	# post information of a specific type
	server.post '/info/:info-type', (req, res, next) ->
		# insert the info into the database
		# insert the multiplexing opstream into the database

		new Info_Model req.account, () ->
			@create req.params['info-type'], req.body, (err) ->
				if err then throw err

				res.send {
					status: 'ok',
					statusText: 'Information recieved'
				}

	# list all info handlers for this info-type
	server.get '/info/:info-type/handlers', (req, res, next) ->
		# todo: handle pagination nicely!
		new Infohandler_Model req.account, () ->
			type = req.params['info-type']
			@loadPaginated {info_type: type}, req, (err, response) ->
				if err then throw err
				res.send response

	# update a handler for this info-type
	server.post '/info/:info-type/handler/:handler-id', (req, res, next) ->
		# insert a handler config.
		# insert an opstream for turning configs into opsreams.
		new Infohandler_Model req.account, () ->
			try
				req.body._id = req.params['handler-id']
				@create req.params['info-type'], req.body, (err) =>
					if err then throw err
					res.send {
						status: 'ok',
						statusText: 'The information handler was updated.',
						handler: @export()
					}
			catch e
				server.emit 'uncaughtException', req, res, req.route, e

	# delete a handler for this info-type
	server.del '/info/:info-type/handler/:handler-id', (req, res, next) ->
		# delete the config, the opstream should take care of the rest.
		new Infohandler_Model req.account, () ->
			@remove {_id: req.params['handler-id']}, (err, count) ->
				res.send {
					status: 'ok',
					statusText: 'The information handler was deleted.',
					deleted: count | 0
				}
