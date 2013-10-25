module.exports = (stream, config) ->

	async = require 'async'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	Fact_Model = require models + 'fact_deferred'

	config.models =
		account: Account_Model
		fact: Fact_Model

	account_name = stream.db.databaseName.replace(/^faction_account_/,'')

	_settings = Cache.create 'fact-settings-' + account_name, true, (key, next) ->
		stream.db.collection('fact_settings').find().toArray next

	_hooks = Cache.create 'hooks-' + account_name, true, (key, next) ->
		stream.db.collection('hooks').find().toArray next

	s = +new Date
	t = (args...) ->
		args.push (+new Date) - s
		console.log.apply console.log, args

	return (row, callback) ->
		self = @
		fns = {}
		if not @accountModel?
			fns.account = (next) ->
				new Account_Model () ->
					self.accountModel = @
					@load {_id: account_name}, next

		fns.hooks = (next) ->_hooks.get next
		fns.settings = (next) -> _settings.get next

		return async.series fns, (err, results) =>
			# need to do the following:
			#  - evaluate fact fields.
			#  - send hooks.
			hooks = results.hooks[0].filter (hook) -> hook.fact_type is row.type
			settings = results.settings[0].filter((setting) -> setting._id is row.type).pop()

			new Fact_Model @accountModel, row.type, () ->
				model = @
				@load {_id: row.id}, true, (err, fact = {}) ->

					if err or not fact._id
						return callback err, null

					@addShim () =>
						# evaluate fact data...
						evals = ([key, props] for key, props of settings.field_modes when props.eval)

						evaluate = (arr, next) =>
							[key, props] = arr
							# evaluate the value
							@withMap [], props.map, false, (err, map) =>
								@data.eval props.eval, map, (err, result) =>
									result = result ? props.default ? null
									# send it forward
									next null, {key: key, value: result}

						async.mapSeries evals, evaluate, (err, columns) =>
							fact = JSON.parse JSON.stringify @

							cb = (next) -> next()

							# if we evaluated anytihng, save the fact.
							if columns.length > 0
								cb = (next) =>
									columns.forEach (column) =>
										@data.set.call fact, column.key, column.value

									# remove any foreign columns
									for key of settings.foreign_keys
										@data.del.call fact, key

									@table.save fact, next

							cb (err) =>
								# send to hooks...
								data = hooks.map (hook) ->
									ret =
										hook_id: hook.hook_id,
										fact_type: hook.fact_type
										fact_id: fact._id

									if hook.mode isnt 'snapshot'
										ret.fact_id = (Math.round 999 * Math.random()) + (+new Date)
										ret.data = fact

									return ret
								data = data.filter Boolean

								if data.length > 0
									stream.db.collection('hooks_pending').insert data, (err) ->
										if err
											# duplicate rows arent a problem
											return if err.code is 11000

											console.error 'Add hook error', arguments
											throw err

								callback null, {
									id: row.id
									type: row.type
									updated_fields: (key for key, props of settings.field_modes when props.eval)
									hooks: hooks.map((hook) -> hook.hook_id),
									fact: fact
								}
