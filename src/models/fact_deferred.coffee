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

	@markUpdated = (id, type, account, callback) ->
		jobs.create('fact_update', {
			title: "#{type} - #{id}"
			account: account,
			data: {
				fact_id: id,
				fact_type: type,
				version: null
			}
		}).save (err) -> callback err, id

	markUpdated: (callback) ->
		if @data._id
			Fact_deferred_Model.markUpdated @data._id, @type, @account.data._id, callback
		else
			callback()

	markUpdatedFull: (callback) ->
		jobs.create('fact_update_all', {
			title: @type,
			account: @account.data._id,
			data: {
				fact_type: @type,
				version: null
			}
		}).save (err) -> callback err


	export: ->
		if @data.data
			return @data.data
		return @data

	import: (data, defer, callback) ->
		args = Array::slice.call arguments, 1
		callback = args.pop()
		defer = args.pop() ? true

		@getSettings (err, settings) =>
			@data = {}
			settings.foreign_keys ?= {}
			for key, val of data
				if not settings.foreign_keys[key]?
					@data[key] = val

			if defer
				@defer () =>
					callback err, @data
			else
				callback err, @data

	defer: (callback) ->
		self = @
		@data = new DeferredObject @data or {}
		@getSettings (err, settings) =>
			for key, props of settings.foreign_keys or {}
				delete @data[key]
				@data.defer key, (key, data, next) =>
					props = settings.foreign_keys[key]
					Fact_deferred_Model.parseObject props.query, {fact: self.data}, (err, query) ->
						if err
							return next err
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
			if err or not row
				return callback err, row
			@import row, defer, () =>
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

	loadPaginated: (conditions, req, callback) ->
		super conditions, req, (err, response) ->
			if err
				return callback err, response

			loader = (item, next) ->
				# apply withMap to each item.
				item.withMap req.body.with, req.body.map, next

			async.map response.items, loader, (err, items) ->
				response.items = items
				callback err, response

	addShim: (callback) ->
		file = require('path').resolve __dirname, '../processor/jobs/info/add_shim'
		addShim = require file
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
				next2 err, Boolean result

		condition = condition.data or condition

		async.mapSeries condition.conditions, evalCond, callback


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
			start = +new Date
			@data.eval "this.#{part}", context, (err, result) ->
				next err, result

		async.map _with, get, () =>

			if not map
				return res.send @data

			# next = (cb) -> cb()
			# next = @addShim if shim

			@addShim () =>
				obj = {}
				get = (arg, next) =>
					[key, path] = arg

					def = null
					if Array.isArray path
						def = path[1]
						path = path[0]

					@data.eval path, context, (err, result) =>
						if err then console.log 'WM', @data.data._id, path, err
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

moment = require 'moment'
Fact_deferred_Model.evaluate = (str, context, callback) ->
	context.isAsync = false
	context.async = (val = true) -> context.isAsync = val
	context.complete = (err, str) ->
		context.complete = () -> null
		process.nextTick () -> callback? err, str

	context.moment = moment

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

	errors = []
	iter = (node, next) =>
		Fact_deferred_Model.evaluate node.value, context, (err, newval) =>
			if err
				errors.push err
			else
				node.update newval, true
			next()

	async.each nodes, iter, () ->
		err = (if errors.length then errors else null)
		callback err, obj
