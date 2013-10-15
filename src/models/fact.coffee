async = require 'async'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class Fact_Model extends Model

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
			new Fact_Model req.account, req.params['fact-type'], () ->
				req.model = @
				next()
		else next()

	removeFull: (callback) ->
		@table.drop callback

	load: (query, withFK, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		withFK = args.pop() or false

		self = @

		super query, (err, row, query) ->
			if row and withFK isnt false
				@loadFK withFK, (data) =>
					callback.call @, err, @data, query
			else
				callback.apply @, err, @data, query

	loadAll: (query, withFK, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		withFK = args.pop() or false

		@table.find(query, {_id: 1}).toArray (err, ids) =>
			loader = (row, next) =>
				@_spawn () ->
					@load {_id: row._id}, withFK, next

			async.map ids, loader, callback

	loadFK: (chain, callback) ->
		args = Array::slice.call arguments
		callback = args.pop()
		chain = args.pop()
		self = @

		if not Array.isArray chain
			chain = []
		chain.push self

		@getSettings (err, settings) ->
			if err or not settings or not settings.foreign_keys
				return callback()

			fks = ([key, fk] for key, fk of settings.foreign_keys)

			# load each foreign key in these settings.
			loadFK = (arr, next) ->
				[key, fk] = arr

				for item in chain when item.type is fk.fact_type
					return next()

				cb = (err, data) ->
					self.data[key] = data
					next()

				Fact_Model.parseObject fk.query, {fact: self.data}, (query) =>
					new Fact_Model self.account, fk.fact_type, () ->
						if fk.has is 'one' or query._id?
							@load query, chain, cb #(err) -> cb err, @data
						else
							@loadAll query, chain, cb #(err, data) -> cb err, data

			async.each fks, loadFK, () ->
				callback()


	addShim: (callback) ->
		path = require('path').resolve(__dirname, '../../opstreams/info_mapper/lib/add_shim')
		addShim = require(path)()
		addShim @data, callback

	updateFields: (callback) ->
		@addShim (err, fact) =>
			@getSettings (err, settings) =>
				for key, props of settings.field_modes when props.eval
					result = Fact_Model.evaluate props.eval, {fact: fact}
					fact.set key, result

				@data = fact
				callback.call @, err, fact


	getSettings: (callback) ->
		@settings_cache ?= Cache.create 'fact-settings-' + @account.data._id, true, (key, next) =>
			@db.collection('fact_settings').find().toArray next

		@settings_cache.get (err, settings) =>
			callback err, settings.filter((setting) => setting._id is @type).pop()


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
						new Fact_Model account, type, () ->
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


Fact_Model.evaluate = (str, context, callback) ->
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
Fact_Model.interpolate = (str, context, callback) ->
	(str.match(/\#\{.+?\}/g) or []).forEach (section) =>
		str = str.replace section, Fact_Model.evaluate section.slice(2, -1), context
	return str

###
parseObject: evaluate the object with this context, interpolating keys and evaluating leaves.
	Should transform an object like:
		"orders": "item", "order_#{item.oid}_value": "item.value"
	Into this:
		"orders": {oid: 42, value: 400}, "orders_42_value": 400
###
Fact_Model.parseObject = (obj, context, callback) ->
	# interpolate keys
	obj = JSON.parse (JSON.stringify obj), (key, value) =>
		if Object::toString.call(value) is '[object Object]'
			for k, v of value
				delete value[k]
				k = Fact_Model.interpolate k, context
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
		Fact_Model.evaluate node.value, context, (err, newval) =>
			next err, node.update newval, true

	async.each nodes, iter, () -> callback obj
