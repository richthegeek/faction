check = require('validator').check
crypto = require 'crypto'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class InfoHandler_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info_handlers', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new InfoHandler_Model req.account, () ->
			req.model = @
			next()

	setup: () ->
		@table.ensureIndex {handler_id: 1, info_type: 1}, {unique: true}, () -> null
		@table.ensureIndex {fact_type: 1}, {}, () -> null

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

	save: () ->
		# mark the handler cache as stale
		Cache.create('info-handlers-' + @account.data._id, false, (key, next) => @table.find().toArray next).stale()
		super

	export: () ->
		return {
			handler_id: @data.handler_id,
			fact_type: @data.fact_type,
			fact_identifier: @data.fact_identifier,
			track: @data.track
		}
