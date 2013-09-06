check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class InfoHandler_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info_handlers', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new InfoHandler_Model req.account, () ->
			req.model = @
			next()

	validate: (data) ->
		check(data.fact_type, {
			notEmpty: 'An information-handler should have a fact_type property',
		}).notEmpty()

		check(data.fact_identifier, {
			notEmpty: 'An information-handler should have a fact_identifier property',
		}).notEmpty()

		if not data.track or typeof data.track isnt 'object'
			throw 'An information-handler should have a track property defining how data is applied to facts.'

		if not data.handler_id
			throw 'An information-handler must have an ID defined. (This error should not be seen)'

	create: (type, info, callback) ->
		if typeof info is 'function'
			callback = info
			info = {}

		info.info_type = type
		delete info._id

		@data = info
		@save callback

	export: () ->
		return {
			handler_id: @data.handler_id,
			fact_type: @data.fact_type,
			fact_identifier: @data.fact_identifier,
			track: @data.track
		}
