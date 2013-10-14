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

			bindFunctions data
			data.getSettings = () -> settings

			# load foreign keys
			fns = for k, fk of settings.foreign_keys
				do (key, fk) ->
					fns.push (next) ->
						loadFK fk, (err, row) ->
							next err, data.set(key, row)

			async.parallel fns, loadFKs, () =>
				callback null, data
