check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class InfoHandler extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info_handlers', callback

	create: (type, info, callback) ->
		if typeof info is 'function'
			callback = info
			info = {}

		info.info_type = type

		if not info._id
			throw 'An information-handler must have an ID defined.'

		check(info.fact_type, {
			notEmpty: 'An information-handler should have a fact_type property',
		}).notEmpty()

		check(info.fact_identifier, {
			notEmpty: 'An information-handler should have a fact_identifier property',
		}).notEmpty()

		if not info.track or typeof info.track isnt 'object'
			throw 'An information-handler should have a track property defining how data is applied to facts.'

		@data = info
		@save callback


