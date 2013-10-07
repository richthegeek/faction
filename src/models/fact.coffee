async = require 'async'
Model = require './model'
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

	load: (query, shim, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		shim = args.pop() or false

		super query, () ->
			@addShim callback

	loadAll: (query, shim, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		shim = args.pop() or false

		@table.find(query, {_id: 1}).toArray (err, ids) =>
			loader = (row, next) =>
				@_spawn () ->
					@load {_id: row._id}, shim, next

			async.map ids, loader, callback

	@getTypes = (account, callback) ->
		# open a connection to the database.
		mongodb.open account.dbname(), (err, db) ->
			# list all collections with the right name...
			db.collectionNames (err, collections) ->
				len = db.databaseName.length + 1
				result = (for coll in collections when 'facts_' is coll.name.substring len, len + 5
					coll.name.slice len + 5
				)

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

	bindFunctions: (data = @export()) ->
		moment = require 'moment'
		traverse = require 'traverse'

		bind_array = (value) ->
			if (1 for item in value when item._value? and item._date?).length > 0
				value.over = (period, time) ->
					end = Number(time) or new Date().getTime()

					if bits = period.match(/^([0-9]+) (second|minute|hour|day|week|month|year)/)
						duration = moment.duration Number(bits[1]), bits[2]
						start = end - duration
						if 0 is duration.as 'milliseconds'
							throw 'Invocation of Array.over with invalid duration string.'

					else if seconds = Number(period)
						start = end - seconds

					else
						throw 'Invocation of Array.over with invalid duration value.'

					@betweenDates start, end

				value.before = (time) -> @betweenDates 0, time
				value.after = (time) -> @betweenDates time, new Date
				value.betweenDates = (start, end) -> bind_array @filter (item) -> new Date(start) <= (new Date item._date or new Date()) <= new Date(end)


			value.values = (column) ->
				return bind_array @filter((v) -> typeof v isnt 'function').map (v) ->
					v = v._value ? v
					return (column and v[column] or v)

			value.sum  = (column) -> @values(column).reduce ((pv, cv) -> pv + (cv | 0)), 0
			value.max  = (column) -> @values(column).reduce ((pv, item) -> Math.max pv, item | 0), Math.max()
			value.min  = (column) -> @values(column).reduce ((pv, item) -> Math.min pv, item | 0), Math.min()
			value.mean = (column) -> @sum(column) / @values(column).length

			compare = (column, val, fn) ->
				args = Array::slice.call arguments
				fn = args.pop()
				val = args.pop()
				column = args.pop()
				@values(column).filter (v) -> fn val, v
			value.gt  = (column, val) -> compare.call @, column, val, (val, v) -> v > val
			value.gte = (column, val) -> compare.call @, column, val, (val, v) -> v >= val
			value.lt  = (column, val) -> compare.call @, column, val, (val, v) -> v < val
			value.lte = (column, val) -> compare.call @, column, val, (val, v) -> v <= val

			value.match = (params) ->
				# allow calling like (key, val, key, val, key, val)
				args = Array::slice.call arguments
				if args.length > 1 and typeof args[0] is 'string'
					params = {}
					while args.length >= 2
						params[args.shift()] = args.shift()

				@values().filter (row) ->
					for key, val of params
						# if it's a regex-like string (/....../) try parse it.
						if typeof val is 'string' and val.match /^\/.+\/$/
							try
								val = new RegExp val.slice(1, -1)
							catch e then null

						val.test ?= (v) -> val is v
						if not val.test row[key]
							return false
					return true

			return value

		traverse(data).forEach (value) ->
			type = Object::toString.call(value).slice(8, -1)

			if type is 'Array'
				@update bind_array value

		return data

	# add various functions to a fact:
	#  - get(path): return values matching the given path
	#  - Array functions:
	#		- general: sum, max, min, mean, gt, gte, lt, lte, values
	#		- temporal: over, before, after, betweendates, values
	addShim: (callback) ->
		table = @table
		type = @type

		FKCache = {}
		loadFK = (properties, callback) =>
			if FKCache[properties.key]?
				return process.nextTick () -> callback null, FKCache[properties.key]

			next = (err, data) ->
				if data
					FKCache[properties.key] = data
				return callback err, data

			InfoMapping_Model.parseObject properties.query, {fact: @data}, (query) =>
				new Fact_Model @account, properties.fact_type, () ->
					if query._id? or properties.has is 'one'
						@load query, true, next
					else
						@loadAll query, true, next

		cache = require 'shared-cache'
		_settings = cache.create 'fact-settings-' + @account.data._id, true, (key, next) =>
			@db.collection('fact_settings').find().toArray next

		_settings.get (err, allSettings) =>
			settings = (set for set in allSettings when set._id is type).pop() or {foreign_keys: []}

			# copy the key over.
			fk_arr = []
			for k, v of settings.foreign_keys
				settings.foreign_keys[k].key = k
				settings.foreign_keys[k].autoload ?= false
				fk_arr.push settings.foreign_keys[k]

			@bindFunctions @data
			@data.getSettings = () -> settings
			@data.get = (args..., callback) ->
				result = this

				# allow arguments to be specified like paths, ie "user/name" as well as arrays
				args = [].concat.apply [], args.map (arg) -> arg.split /[\.\/]/

				i = 0
				iter = (arg, next) =>
					i++

					extract = (obj, cb) =>
						if typeof obj is 'function'
							return obj cb
						cb null, (v for k, v of obj or {})

					if arg is '*'
						extract result, (err, res) ->
							next null, result = res

					else if result[arg]?
						if typeof result[arg] is 'function'
							return result[arg] (err, res) ->
								next null, result = res
						next null, result = result[arg]

					else if i is 1 and settings.foreign_keys[arg]?
						loadFK.call this, settings.foreign_keys[arg], (err, res) ->
							next err, result = res

					else if Array.isArray(result)
						ii = (r, n) -> extract r[arg], n
						async.map result, ii, (err, res) ->
							next err, result = [].concat.apply [], res

				async.eachSeries args, iter, (err) -> callback err, result

			loadAutoFKs = (fk, next) =>
				if fk.autoload isnt true
					return next()

				loadFK fk, (err, data) =>
					if data
						@data[fk.key] = data
					next()

			async.each fk_arr, loadAutoFKs, () =>
				callback null, @data
