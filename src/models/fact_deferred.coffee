async = require 'async'
Model = require './model'
Cache = require 'shared-cache'
DeferredObject = require 'deferred-object'

wrapArray = require '../lib/wrapArray'

module.exports = class Fact_deferred_Model extends Model

	constructor: (@account, @type, callback) ->
		@type = type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60)

		super account.dbname(), @collectionname(), (self, db, coll) ->
			callback.apply @, arguments

	_spawn: (callback) ->
		new @constructor @account, @type, callback

	@collectionname = @::collectionname = (type = @type) ->
		'facts_' + type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60)

	@route = (req, res, next) ->
		if req.params['fact-type']
			new Fact_deferred_Model req.account, req.params['fact-type'], () ->
				req.model = @
				next()
		else next()

	removeFull: (callback) ->
		@table.drop callback

	markUpdated: (callback) ->
		if @data._id
			@db.collection('fact_updates').insert {
				type: @type,
				id: @data._id,
				time: +new Date
			}, callback
		else
			callback()

	markUpdatedFull: (callback) ->
		type = @type
		collection = @db.collection('fact_updates')
		# get all ids
		@table.aggregate {$group: {_id: null, ids: $push: '$_id'}}, (err, result) ->
			ids = result[0].ids
			insert = (id, next) =>
				collection.insert {
					type: type,
					id: id,
					time: +new Date
				}, next
			async.map ids, insert, (err, result) ->
				id = (result or []).filter((v) -> v?[0]?.id?).map((v) -> v[0].id)
				callback err, id

	export: ->
		if @data.data
			return @data.data
		return @data

	import: (data, callback) ->
		@data = data or {}
		@defer callback

	defer: (callback) ->
		self = @
		@data = new DeferredObject @data or {}
		@getSettings (err, settings) =>
			for key, props of settings.foreign_keys or {}
				@data.defer key, (key, data, next) =>
					props = settings.foreign_keys[key]
					Fact_deferred_Model.parseObject props.query, {fact: self.data}, (query) ->
						new Fact_deferred_Model self.account, props.fact_type, () ->
							if props.has is 'one' or query._id?
								@load query, next
							else
								@loadAll query, next
			callback.call @, @data

	load: (query, defer, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		defer = args.pop() ? true

		if (query instanceof mongodb.ObjectID) or (typeof query in ['string', 'number'])
			query = {_id: query}

		@table.findOne query, (err, row) =>
			@data = row or {}
			if err or not row
				return callback err, row

			if defer
				return @defer () =>
					callback.call @, err, @data, query

			callback.call @, err, @data, query

	loadAll: (query, defer, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		defer = args.pop() ? true

		@table.find(query, {_id: 1}).toArray (err, ids) =>
			loader = (row, next) =>
				@_spawn () ->
					@load {_id: row._id}, defer, next

			async.map ids, loader, (err, rows) ->
				callback.call @, err, wrapArray rows

	addShim: (callback) ->
		path = require('path').resolve(__dirname, '../../opstreams/info_mapper/lib/add_shim')
		addShim = require(path)()
		addShim @data, callback

	updateFields: (callback) ->
		@addShim (err, fact) =>
			@getSettings (err, settings) =>
				for key, props of settings.field_modes when props.eval
					result = Fact_deferred_Model.evaluate props.eval, {fact: fact}
					fact.set key, result

				@data = fact
				callback.call @, err, fact

	evaluateCondition: (condition, context, callback) ->
		args = Array::slice.call arguments
		callback = args.pop() or -> null
		context = args.pop() or {}

		fact = @

		evalCond = (cond, next2) ->
			fact.data.eval cond, context, (err, result) ->
				next2 err, result

		async.mapSeries condition.data.conditions, evalCond, callback


	withMap: (_with, map, context, shim, callback) ->
		args = Array::slice.call(arguments, 2)
		callback = args.pop()
		shim = args.pop() or true

		if typeof shim isnt 'boolean'
			context = shim
			shim = true
		else
			context = args.pop() or {}

		_with = [].concat.call [], _with ? []
		map = map or {}

		get = (part, next) =>
			@data.eval "this.#{part}", context, (err, result) ->
				next err, result

		async.map _with, get, () =>

			if not map
				return res.send @data

			next = (cb) -> cb()
			next = @addShim if shim

			next () =>
				obj = {}
				get = (arg, next) =>
					[key, path] = arg

					def = null
					if Array.isArray path
						def = path[1]
						path = path[0]

					@data.eval path, context, (err, result) ->
						return next null, obj[key] = context[key] = result or def

				maps = ([key, path] for key, path of map)
				if maps.length > 0
					maps.unshift ['_id', 'this._id']

					async.mapSeries maps, get, () =>
						callback null, obj
				else
					callback null, @data


	getSettings: (callback) ->
		@settings_cache ?= Cache.create 'fact-settings-' + @account.data._id, true, (key, next) =>
			@db.collection('fact_settings').find().toArray next

		@settings_cache.get (err, settings) =>
			callback err, settings.filter((setting) => setting._id is @type).pop() or {}


	@getTypes = (account, callback) ->
		# open a connection to the database.
		mongodb.open account.dbname(), (err, db) ->
			# list all collections with the right name...
			db.collectionNames (err, cl) ->
				collections = cl

				rename = (row) -> return row.name.split('.').pop()
				filter = (name) -> return name.slice(0, 6) is 'facts_'
				trim   = (name) -> return name.slice(6)

				result = cl.map(rename).filter(filter).map(trim)

				result.detailed = (callback) ->
					iter = (type, next) ->
						new Fact_deferred_Model account, type, () ->
							@table.count (err, size) ->
								next err, {
									fact_type: type,
									fact_sources: 'todo',
									count: size,
									nextPage: "/facts/#{type}"
								}

					async.map result, iter, (err, info) ->
						obj = {}
						obj[fact.fact_type] = fact for fact in info or []
						callback err, obj

				callback err, result


Fact_deferred_Model.evaluate = (str, context, callback) ->
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
Fact_deferred_Model.interpolate = (str, context, callback) ->
	(str.match(/\#\{.+?\}/g) or []).forEach (section) =>
		str = str.replace section, Fact_deferred_Model.evaluate section.slice(2, -1), context
	return str

###
parseObject: evaluate the object with this context, interpolating keys and evaluating leaves.
	Should transform an object like:
		"orders": "item", "order_#{item.oid}_value": "item.value"
	Into this:
		"orders": {oid: 42, value: 400}, "orders_42_value": 400
###
Fact_deferred_Model.parseObject = (obj, context, callback) ->
	# interpolate keys
	obj = JSON.parse (JSON.stringify obj), (key, value) =>
		if Object::toString.call(value) is '[object Object]'
			for k, v of value
				delete value[k]
				k = Fact_deferred_Model.interpolate k, context
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
		Fact_deferred_Model.evaluate node.value, context, (err, newval) =>
			next err, node.update newval, true

	async.each nodes, iter, () -> callback obj
