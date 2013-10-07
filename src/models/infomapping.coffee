async = require 'async'
crypto = require 'crypto'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class InfoMapping_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info_mappings', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new InfoMapping_Model req.account, () ->
			req.model = @
			next()

	setup: () ->
		@table.ensureIndex {mapping_id: 1, info_type: 1}, {unique: true}, () -> null
		@table.ensureIndex {fact_type: 1}, {}, () -> null

	validate: (data, callback) ->
		if not data.fact_type
			return callback 'An information-mapping should have a fact_type property.'

		if not data.fact_identifier
			return callback 'An information-mapping should have a fact_identifier property defining how a fact is loaded.'

		if not data.fields or typeof data.fields isnt 'object'
			return callback 'An information-mapping should have a fields property defining how data is mapped to facts.'

		if not data.mapping_id
			return callback 'An information-mapping must have an ID defined. (This error should not be seen).'

		callback()

	save: () ->
		# mark the mapping cache as stale
		Cache.create('info-mappings-' + @account.data._id, false, (key, next) => @table.find().toArray next).stale()
		super

	export: () ->
		return {
			mapping_id: @data.mapping_id,
			fact_type: @data.fact_type,
			fact_identifier: @data.fact_identifier,
			fields: @data.fields
		}

	setup: ->
		path = require 'path'
		@db.addStreamOperation {
			_id: 'info_handlers',
			type: 'untracked',
			operations: [{
				modular: true
				operation: path.resolve(__dirname, '../../opstreams/info_mapper')
			}],
			sourceCollection: 'info',
			targetCollection: 'fact_updates'
		}
