module.exports = (stream, config) ->

	async = require 'async'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	InfoMapping_Model = require models + 'infomapping'
	Fact_Model = require models + 'fact_deferred'

	config.models =
		account: Account_Model
		infomapping: InfoMapping_Model
		fact: Fact_Model

	account_name = stream.db.databaseName.replace(/^faction_account_/,'')

	_mappings = Cache.create 'info-mappings-' + account_name, true, (key, next) ->
		stream.db.collection('info_mappings').find().toArray next

	_settings = Cache.create 'fact-settings-' + account_name, true, (key, next) ->
		stream.db.collection('fact_settings').find().toArray (err, settings) ->
			if err or not settings
				return next err, settings

			# create indexes on all thse foreign columns.
			collections = {}
			ensureIndex = (fk, next) ->
				collections[fk.fact_type] ?= stream.db.collection Fact_Model.collectionname fk.fact_type

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

	s = +new Date
	t = (args...) ->
		args.push (+new Date) - s
		console.log.apply console.log, args

	return (row, callback) ->
		self = @
		config.time = row._id.getTimestamp() or new Date

		mergeFacts = require('./merge_facts')(stream, config, row)
		markForeignFacts = require('./mark_foreign_facts')(stream, config, row)
		addShim = require('./add_shim')(stream, config, row)
		{evaluate, parseObject} = require('./eval')(stream, config, row)

		fns = []

		if not @accountModel?
			fns.push (next) ->
				new Account_Model () ->
					self.accountModel = @
					@load {_id: account_name}, next

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

		fns.push (skip..., next) ->_mappings.get (err, mappings) -> next err, mappings
		fns.push (mappings, skip..., next) -> _settings.get (err, settings) -> next err, mappings, settings

		return async.waterfall fns, (err, mappings, settings) =>
			account = @accountModel
			mappings = mappings.filter (mapping) -> mapping.info_type is row._type

			# t 'start', mappings.length

			parseMappings = (mapping, next) ->
				query = _id: evaluate mapping.fact_identifier, {info: row}

				if not query._id?
					return next()

				new Fact_Model account, mapping.fact_type, () ->
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
				set = (s for s in settings when s._id is info.model.type).pop()

				# remove this stuff, it gets in the way.
				for key of set.foreign_keys
					info.fact.del key

				# info.model is a Fact_Model instance. Reimport to add re-add the shim...
				fact = mergeFacts set, info.fact.data, info.info

				for key, mode of set.field_modes when mode is 'delete'
					info.fact.del.call fact, key

				info.fact.set.call fact, '_updated', new Date

				# save this into the target collection, move on
				info.model.table.save fact, (err) ->
					# create additional fact updates for FKs
					list = (fk for field, fk of set.foreign_keys or {})

					iter_wrap = (fk, next) -> markForeignFacts fk, fact, next

					# debug
					iter_wrap = (fk, next) -> next null, []

					async.map list, iter_wrap, (err, updates) ->
						updates = updates.filter (v) -> v and v.length > 0
						updates.push {
							id: fact._id,
							type: info.mapping.fact_type,
							time: +new Date
						}
						# write to fact_updates
						next err, updates


			async.map mappings, parseMappings, (err, result) ->
				# flatten results into single array
				result = [].concat.apply([], result).filter (r) -> !! r

				async.map result, combineMappings, (err, result) ->
					# double concat...
					result = [].concat.apply([], result)
					result = [].concat.apply([], result)
					result = result.filter (r) -> (!! r) and not Array.isArray r

					callback err, result
