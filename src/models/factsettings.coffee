check = require('validator').check
crypto = require 'crypto'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class FactSettings_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'fact_settings', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new FactSettings_Model req.account, () ->
			req.model = @
			next()

	validate: (data, callback) ->
		modes = ['all', 'newest', 'oldest', 'max', 'min']
		for field, mode of data.field_modes
			if mode not in modes
				return callback 'Field mode must be one of (' + modes.join(', ') + ')'

		@data.primary_key = data.primary_key ?= ['_id']
		if not Array.isArray(data.primary_key) or data.primary_key.length is 0
			return callback 'The primary_key field must be an array of one or more field names'

		callback()

	export: () ->
		return {
			fact_type: @data._id,
			field_modes: @data.field_modes,
			primary_key: @data.primary_key
		}
