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

		{evaluate, parseObject} = require('./eval')(stream, config, row)


		fn = (next) -> next()
		if not @accountModel?
			fn = (next) ->
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

		return fn () =>
			account = @accountModel
			_mappings.get (err, mappings) ->
				_settings.get (err, settings) ->
					parseMappings = (mapping, next) ->
						if mapping.info_type isnt row._type
							return next()

						query = _id: evaluate mapping.fact_identifier, {info: row}

						new Fact_Model account, mapping.fact_type, () ->
							model = @
							@load query, true, (err, fact = {}) ->
								if err
									return next err

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
						setting = info.fact.getSettings()
						info.model.import mergeFacts(setting, info.fact, info.info), () ->
							@addShim (err, fact) ->

								# save this into the target collection, move on
								info.model.table.save fact, (err) ->
									# create additional fact updates for FKs
									list = (fk for field, fk of setting.foreign_keys or {})

									iter_wrap = (fk, next) -> markForeignFacts fk, fact, next
									async.map list, iter_wrap, (err, updates) ->
										updates = updates.filter (v) -> v and v.length > 0
										updates.push {
											id: fact._id,
											type: info.mapping.fact_type,
											time: +new Date
										}
										console.log 'Nearly', updates
										return
										# write to fact_updates
										next err, updates


					async.map mappings, parseMappings, (err, result) ->
						# flatten results into single array
						result = [].concat.apply([], result).filter (r) -> !! r

						async.map result, combineMappings, () ->
							console.log 'COMPLETE', arguments

						# callback
