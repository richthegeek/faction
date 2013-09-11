Cache = require 'shared-cache'

module.exports = (server) ->

	# post information of a specific type
	# uses the caching module to keep the list of handlers up to date without always grabbing it.
	server.post '/info/:info-type', Info_Model.route, (req, res, next) ->
		handlers = Cache.create 'info-handlers-' + req.account.data._id, true, (key, next) ->
			new Infohandler_Model req.account, () ->
				@table.find().toArray next

		req.model.create req.params['info-type'], req.body, (err) ->
			if err then throw err

			handlers.get (err, list, hit) ->
				res.send {
					status: 'ok',
					statusText: 'Information recieved',
					handlers: (Infohandler_Model.export(handler) for handler in list when handler.info_type is req.params['info-type'])
				}

	# list all info handlers for this info-type
	server.get '/info/:info-type/handlers', Infohandler_Model.route, (req, res, next) ->
		req.model.loadPaginated req.params.asQuery(), req, (err, response) ->
			if err then throw err
			res.send response

	# update a handler for this info-type
	server.post '/info/:info-type/handlers/:handler-id', Infohandler_Model.route, (req, res, next) ->
		# insert a handler config.
		# insert an opstream for turning configs into opstreams.
		delete req.body._id
		req.body.info_type = req.params['info-type']
		req.body.handler_id = req.params['handler-id']
		req.model.update req.params.asQuery(), req.body, (err, updated) =>
			if err then throw err
			res.send {
				status: 'ok',
				statusText: 'The information handler was ' + (updated and 'updated.' or 'created.'),
				handler: req.model.export()
			}

	# delete a handler for this info-type
	server.del '/info/:info-type/handlers/:handler-id', Infohandler_Model.route, (req, res, next) ->
		# delete the config, the opstream should take care of the rest.
		req.model.remove req.params.asQuery(), (err, count) ->
			res.send {
				status: 'ok',
				statusText: 'The information handler was deleted.',
				deleted: count | 0
			}
