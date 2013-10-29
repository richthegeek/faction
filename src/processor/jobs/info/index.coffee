async = require 'async'
Cache = require 'shared-cache'

module.exports = (job, done) ->

	job.progress 0, 3

	account = null
	accountID = job.data.account
	time = new Date parseInt job.created_at
	row = job.data.data

	mergeFacts = require './merge_facts'
	markForeignFacts = require './mark_foreign_facts'
	addShim = require './add_shim'
	{evaluate, parseObject} = require './eval'


	fns = {}
	fns.account = (next) ->
		loadAccount accountID, (err, acc) ->
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

		mappings = results.mappings.filter (mapping) -> mapping and mapping.info_type is row._type
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
			query = _id: evaluate mapping.fact_identifier, {info: row}

			if not query._id?
				return next()

			new Fact_deferred_Model account, mapping.fact_type, () ->
				model = @
				@load query, false, (err, fact = {}) =>
					if err
						return next err

					@addShim (err, fact) ->
						delete row._type
						delete row._id if Object::toString.call(row._id) is '[object Object]'

						parseObject mapping.fields, {info: row, fact: fact}, (obj) ->
							obj._id = query._id

							next null, {
								model: model
								fact: fact or {},
								mapping: mapping,
								info: obj
							}

		combineMappings = (info, next) ->
			set = (s for s in settings when s._id is info.model.type).pop() or {foreign_keys: {}}

			# remove this stuff, it gets in the way.
			for key of set.foreign_keys
				info.fact.del key

			# info.model is a Fact_Model instance. Reimport to add re-add the shim...
			set.time = time
			fact = mergeFacts set, info.fact, info.info

			for key, mode of set.field_modes when mode is 'delete'
				info.fact.del.call fact, key

			info.fact.set.call fact, '_updated', new Date

			# save this into the target collection, move on
			info.model.table.save fact, (err) ->
				next err, {
					fact_id: fact._id,
					fact_type: info.mapping.fact_type,
					version: fact._updated
				}

		async.map mappings, parseMappings, (err, result) ->

			job.progress 2, 3

			# flatten results into single array
			result = [].concat.apply([], result).filter (r) -> !! r

			async.map result, combineMappings, (err, result) ->
				job.progress 3, 3

				# double concat...
				result = [].concat.apply([], result)
				result = [].concat.apply([], result)
				result = result.filter (r) -> (!! r) and not Array.isArray r

				for row in result
					job = jobs.create 'fact_update', {
						title: "#{row.fact_type} - #{row.fact_id}"
						account: accountID,
						data: row
					}
					job.save()

				done err, result