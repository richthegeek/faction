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


	@::eval = @eval = (str, context, callback) ->
		context.isAsync = false
		context.async = (val = true) -> context.isAsync = val
		context.complete = (err, str) ->
			context.complete = () -> null
			process.nextTick () -> callback? err, str

		fn = () ->
			try
				`with(context) { str = eval(str) }`
			catch e
				return context.complete e, str

			if not context.isAsync
				context.complete null, str
				return str
			return null

		return do fn.bind {}

	###
	interpolate: evaluate demarcated sections of a string
	###
	@::interpolate = @interpolate = (str, context, callback) ->
		(str.match(/\#\{.+?\}/g) or []).forEach (section) =>
			str = str.replace section, InfoMapping_Model.eval section.slice(2, -1), context
		return str

	###
	parseObject: evaluate the object with this context, interpolating keys and evaluating leaves.
		Should transform an object like:
			"orders": "item", "order_#{item.oid}_value": "item.value"
		Into this:
			"orders": {oid: 42, value: 400}, "orders_42_value": 400
	###
	@::parseObject = @parseObject = (obj, context, callback) ->
		# interpolate keys
		obj = JSON.parse (JSON.stringify obj), (key, value) =>
			if Object::toString.call(value) is '[object Object]'
				for k, v of value
					delete value[k]
					k = InfoMapping_Model.interpolate k, context
					value[k] = v
			return value

		# collect leaves to evaluate
		nodes = []
		traverse = require 'traverse'
		traverse(obj).forEach (val) ->
			if @isLeaf
				@value = val
				nodes.push @

		iter = (node, next) =>
			InfoMapping_Model.eval node.value, context, (err, newval) =>
				next err, node.update newval, true

		async.each nodes, iter, () -> callback obj



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
