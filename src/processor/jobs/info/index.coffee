async = require 'async'
Cache = require 'shared-cache'
moment = require 'moment'

mergeFacts = require './merge_facts'
markForeignFacts = require './mark_foreign_facts'
addShim = require './add_shim'
{evaluate, parseObject} = require './eval'
{getColumn, setColumn, deleteColumn} = require './column_ops'

module.exports =

	concurrency: 1
	timeout: 1000

	exec: (job, done) ->
		job.progress 0, 3

		account = null
		accountID = job.data.account
		time = new Date parseInt job.created_at
		row = job.data.data

		fns = {}
		fns.account = (next) ->
			loadAccount accountID, (err, acc) ->
				if err or not acc
					return console.log 'Failed to get account', err acc
				account = acc
				next err

		fns.setup = (next) ->
			account.mappings ?= Cache.create 'info-mappings-' + accountID, true, (key, next) ->
				account.database.collection('info_mappings').find().toArray next

			account.settings ?= Cache.create 'fact-settings-' + accountID, true, (key, next) ->
				account.database.collection('fact_settings').find().toArray (err, settings) ->
					if err or not settings
						return next err, settings

					# create indexes on all thse foreign columns.
					collections = {}
					ensureIndex = (fk, next) ->
						collections[fk.fact_type] ?= account.database.collection Fact_Model.collectionname fk.fact_type

						index = {}
						for key, val of fk.query
							index[key] = 1

						if index._id
							return next()

						collections[fk.fact_type].ensureIndex index, next

					fks = []
					for setting in settings
						for key, fk of setting.foreign_keys
							fks.push fk

					async.map fks, ensureIndex, () ->
						next err, settings

			next()

		fns.mappings = (next) -> account.mappings.get (e, r) -> next e, r
		fns.settings = (next) -> account.settings.get (e, r) -> next e, r

		async.series fns, (err, results) ->
			job.progress 1, 3

			mappings = results.mappings.filter (mapping) -> mapping and (not mapping.disabled) and mapping.info_type is row._type
			settings = results.settings

			###
			A sample mapping:
				info_type: 'visit',
				fact_type: 'sessions',
				fact_identifier: 'info.sid',
				fields:
					uid: 'info.uid'
					visits:
						url: 'info.url',
						time: 'new Date'

			A sample fact setting:
				fact_type: 'sessions'
				field_modes:
					actions: 'all'
					score:
						eval: "
							async();
							http.request("http://trakapo.com/score", {})

						"
				foreign_keys:
					user:
						fact_type: 'users'
						has: 'one'
						query:
							_id: 'fact.uid'

			With this we need to:
			 - find the fact_identifier in the facts_sessions collection
			 - load the fact settings for the "sessions" fact (cache!)
			 - merge the new info into the existing fact
			 - save, ping any FKs as updated.
			###

			# t 'start', mappings.length

			parseMappings = (mapping, next) ->
				context =
					info: row
					moment: moment
					url: (value, key = 'href') -> require('url').parse(value, true)[key]

				query = _id: evaluate mapping.fact_identifier, context

				if mapping.debug
					console.log 'Query', query

				if not query._id?
					return next()

				mapping.update_only = !! (mapping.update_only ? false)
				mapping.conditions ?= []

				new Fact_deferred_Model account, mapping.fact_type, () ->
					model = @
					@load query, true, (err, fact = {}) =>
						if err
							return next err

						if (mapping.update_only is true) and not fact
							console.log 'Skip due to update_only', mapping.fact_type, query
							return next()

						@addShim (err, fact) =>
							delete row._type
							delete row._id if Object::toString.call(row._id) is '[object Object]'

							# copy fact onto previously defined context
							context.fact = fact

							evalCond = (cond, next) -> Fact_deferred_Model.evaluate cond, context, next
							async.map mapping.conditions, evalCond, (err, conds) ->
								# if an error occured, treat it as a conditions failure
								conds.push not err
								pass = conds.every Boolean
								if not pass
									if mapping.debug
										console.log 'Skip due to condition failure', "\n\t" + mapping.conditions.map((v, i) -> [v, !! conds[i]].join ' ').join("\n\t")
									return next()

								parseObject mapping.fields, context, (obj) ->
									obj._id = query._id

									if mapping.debug
										console.log 'Mapped', mapping, obj

									for key, val of obj when key.indexOf('.') >= 0
										delete obj[key]
										setColumn obj, key, val

									next null, {
										model: model
										fact: fact or {},
										mapping: mapping,
										info: obj
									}

			combineMappings = (info, next) ->
				set = (s for s in settings when s._id is info.model.type).pop() or {foreign_keys: {}}


				set.time = time
				merge = mergeFacts set, info.fact.data, info.info
				# fact is kinda not used, other than getting the ID. Consider removing to get rid of xtend cost.
				fact = merge.fact

				# updates is an array of field updates. Conflicts shouldn't occur, but who knows
				# to avoid conflicts, it comes in as a map of "field name" to action.
				# Conflicts can still occur if two things affect the same field with different names (foo[0] and foo.0, for example)
				updates = merge.updates

				# remove this stuff, it gets in the way.
				console.log 'yep', 1
				for key of set.foreign_keys
					delete updates[key]
				console.log 'yep', 2

				updates._updated = {type: '$set', value: time}
				fact._updated = time

				if not fact._id
					if info.mapping.debug
						console.log 'No Fact ID', fact
					return next()

				# save this into the target collection, move on
				delete updates._id

				updateObj = {}
				for key, opts of updates when opts
					updateObj[opts.type] ?= {}
					updateObj[opts.type][key] = opts.value

				query = {_id: fact._id}
				options = {upsert: true}

				if info.mapping.debug
					console.log 'Write', query, updateObj

				info.model.table.update query, updateObj, options, (err) ->
					next err, {
						fact_id: fact._id,
						fact_type: info.mapping.fact_type,
						version: fact._updated
					}

			async.map mappings, parseMappings, (err, result) ->
				if err
					return done err

				job.progress 2, 3

				# flatten results into single array
				result = [].concat.apply([], result).filter Boolean

				async.map result, combineMappings, (err, result) ->
					job.progress 3, 3

					# double concat...
					result = [].concat.apply([], result)
					result = [].concat.apply([], result)
					result = result.filter(Boolean).filter (r) -> not Array.isArray r

					for row in result when result
						job = jobs.create 'fact_update', {
							title: "#{row.fact_type} - #{row.fact_id}"
							account: accountID,
							data: row
						}
						job.save()

					done err, result
