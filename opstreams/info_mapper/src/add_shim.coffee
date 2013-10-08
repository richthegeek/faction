module.exports = (stream, config, row) ->

	cache = require 'shared-cache'
	async = require 'async'
	bindFunctions = require('./bind_functions')(stream, config, row)
	{evaluate, parseObject} = require('./eval')(stream, config, row)

	# add various functions to a fact:
	#  - get(path): return values matching the given path
	#  - Array functions:
	#		- general: sum, max, min, mean, gt, gte, lt, lte, values
	#		- temporal: over, before, after, betweendates, values
	return (data, account, db, table, type, callback) ->

		FKCache = {}
		loadFK = (properties, callback) =>
			if FKCache[properties.key]?
				return process.nextTick () -> callback null, FKCache[properties.key]

			next = (err, data) ->
				if data
					FKCache[properties.key] = data
				return callback err, data

			parseObject properties.query, {fact: data}, (query) =>
				new config.models.fact account, properties.fact_type, () ->
					if query._id? or properties.has is 'one'
						@load query, true, next
					else
						@loadAll query, true, next

		_settings = cache.create 'fact-settings-' + account.data._id, true, (key, next) =>
			db.collection('fact_settings').find().toArray next

		_settings.get (err, allSettings) =>
			settings = (set for set in allSettings when set._id is type).pop() or {}
			settings.foreign_keys ?= {}

			# copy the key over.
			fk_arr = []
			for k, v of settings.foreign_keys
				settings.foreign_keys[k].key = k
				settings.foreign_keys[k].autoload ?= false
				fk_arr.push settings.foreign_keys[k]

			bindFunctions data
			data.getSettings = () -> settings
			data.get = (args..., callback) ->
				console.log 'GET', args

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

				loadFK fk, (err, row) =>
					if row
						data[fk.key] = row
					next()

			async.each fk_arr, loadAutoFKs, () =>
				callback null, data
