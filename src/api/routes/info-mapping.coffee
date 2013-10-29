
module.exports = (server) ->
	# list all info mappings for this info-type
	server.get '/info/:info-type/mappings', Infomapping_Model.route, (req, res, next) ->
		req.model.loadPaginated req.params.asQuery(), req, ErrorHandler next, (err, response) ->
			res.send response

	# update a mapping for this info-type
	server.post '/info/:info-type/mappings/:mapping-id', Infomapping_Model.route, (req, res, next) ->
		# insert a mapping config.
		# insert an opstream for turning configs into opstreams.
		delete req.body._id
		req.body.info_type = req.params['info-type']
		req.body.mapping_id = req.params['mapping-id']

		req.model.update req.params.asQuery(), req.body, ErrorHandler next, (err, updated) =>
			res.send {
				status: 'ok',
				statusText: 'The information mapping was ' + (updated and 'updated.' or 'created.'),
				mapping: req.model.export()
			}

	# delete a mapping for this info-type
	server.del '/info/:info-type/mappings/:mapping-id', Infomapping_Model.route, (req, res, next) ->
		# delete the config, the opstream should take care of the rest.
		req.model.remove req.params.asQuery(), (err, count) ->
			res.send {
				status: 'ok',
				statusText: 'The information mapping was deleted.',
				deleted: count | 0
			}
