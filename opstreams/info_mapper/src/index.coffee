module.exports = (stream, config) ->

	async = require 'async'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	InfoMapping_Model = require models + 'infomapping'
	Fact_Model = require models + 'fact'

	config.models =
		account: Account_Model
		infomapping: InfoMapping_Model
		fact: Fact_Model

	_mappings = Cache.create 'info-mappings-' + @account, true, (key, next) ->
		stream.db.collection('info_mappings').find().toArray next
	_settings = Cache.create 'fact-settings-' + @account, true, (key, next) ->
		stream.db.collection('fact_settings').find().toArray next

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
					@load {_id: stream.db.databaseName.replace(/^faction_account_/,'')}, next

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

		fns.push (account, skip..., next) -> _mappings.get (err, mappings) -> next err, mappings
		fns.push (mappings, skip..., next) -> _settings.get (err, settings) -> next err, mappings, settings

		return async.waterfall fns, (err, mappings, settings) =>
			account = @accountModel

			parseMappings = (mapping, next) ->
				if mapping.info_type isnt row._type
					return next()

				query = _id: evaluate mapping.fact_identifier, {info: row}

				new Fact_Model account, mapping.fact_type, () ->
					model = @
					@load query, true, (err, fact = {}) ->
						if err
							return next err

						addShim fact, account, @db, @table, @type, (err, fact) ->
							delete row._type
							delete row._id if Object::toString.call(row._id) is '[object Object]'

							parseObject mapping.fields, {info: row, fact: fact}, (obj) ->
								obj._id = query._id

								next null, {
									model: model
									fact: fact,
									mapping: mapping,
									info: obj
								}

			combineMappings = (info, next) ->
				set = info.fact.getSettings()
				# info.model is a Fact_Model instance. Reimport to add re-add the shim...
				info.model.import mergeFacts(set, info.fact, info.info), () ->
					addShim @data, account, @db, @table, @type, (err, fact) ->

						# execute any eval fields of the fact...
						modes = set.field_modes
						for key, props of modes when props.eval
							fact[key] = evaluate props.eval, {fact: fact}

						# delete any "delete" feilds AFTER eval
						for key, mode of modes when mode is 'delete'
							delete fact[key]

						for key of set.foreign_keys
							delete fact[key]

						# save this into the target collection, move on
						info.model.table.save fact, (err) ->
							# create additional fact updates for FKs
							list = (fk for field, fk of set.foreign_keys or {})

							iter_wrap = (fk, next) -> markForeignFacts fk, fact, next
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
