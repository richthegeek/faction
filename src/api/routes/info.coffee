Cache = require 'shared-cache'

module.exports = (server) ->

	# post information of a specific type
	# uses the caching module to keep the list of mappings up to date without always grabbing it.
	server.post '/info/:info-type', Info_Model.route, (req, res, next) ->
		mappings = Cache.create 'info-mappings-' + req.account.data._id, true, (key, next) ->
			new Infomapping_Model req.account, () ->
				@table.find().toArray next

		res.logMessage = req.params['info-type']

		req.model.create req.params['info-type'], req.body, (err) ->
			if err then return next err

			mappings.get ErrorHandler next, (err, list, hit) ->
				res.send {
					status: 'ok',
					statusText: 'Information recieved',
					mappings: (Infomapping_Model.export(mapping) for mapping in list when mapping.info_type is req.params['info-type'])
				}
