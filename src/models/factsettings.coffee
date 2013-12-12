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
		modes = ['all', 'newest', 'oldest', 'max', 'min', 'inc', 'inc_map', 'push', 'push_unique', 'eval']
		for field, mode of data.field_modes
			if typeof mode is 'object'
				mode.mode ?= 'newest'
				mode = mode.mode
				data.field_modes[field].mode = mode
			if mode not in modes
				return callback 'Field mode must be one of (' + modes.join(', ') + '). Was ' + mode

		@data.foreign_keys = data.foreign_keys ?= {}
		for key, props of data.foreign_keys
			if key.match /[^a-z0-9_]/i
				return callback 'Foreign keys names may only contain A-Z, a-z, 0-9, and _'
			if not props.fact_type or not props.query
				return callback 'Foreign keys must have a fact_type and query property.'
			if props.query.toString() isnt '[object Object]' or (k for k of props.query).length is 0
				return callback 'Foreign key query must be a non-empty object.'

		callback()

	export: () ->
		return {
			fact_type: @data._id,
			foreign_keys: @data.foreign_keys,
			field_modes: @data.field_modes,
			primary_key: @data.primary_key
		}
