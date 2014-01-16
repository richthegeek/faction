async = require 'async'
crypto = require 'crypto'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class Hook_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'hooks', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new Hook_Model req.account, () ->
			req.model = @
			next()

	validate: (data, callback) ->
		# TODO: better validation
		# if not data.url
		# 	return callback 'A hook should have a URL property.'

		# if data.options and typeof data.options isnt 'string'
		# 	return callback 'A hook\'s options property must be a string'

		callback()

	save: () ->
		# mark the mapping cache as stale
		Cache.create('hooks-' + @account.data._id, false, (key, next) => @table.find().toArray next).stale()
		super

	export: () ->
		ret = {
			hook_id: @data.hook_id,
			fact_type: @data.fact_type,
			url: @data.url,
			type: @data.type or 'url',
			options: @data.options
		}
		ret.with = @data.with if @data.with?
		ret.map = @data.map if @data.map?
		return ret

	setup: ->
		cb = () -> null
		@table.ensureIndex {hook_id: 1, fact_type: 1}, {unique: true}, cb

		path = require 'path'
		@db.addStreamOperation {
			_id: 'hook_sender',
			type: 'untracked',
			operations: [{
				modular: true
				operation: path.resolve(__dirname, '../../opstreams/hook_sender')
			}],
			sourceCollection: 'hooks_pending',
			targetCollection: 'hooks_sent'
		}
		# for "snapshot" types, the {fact_id,fact_type} pair ensures only the latest hook is sent
		@db.collection('hooks_pending').ensureIndex {fact_id: 1, fact_type: 1}, {unique: true}, cb
