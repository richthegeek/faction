http = require('./http')
q = require 'q'
async = require 'async'
Cache = require 'shared-cache'
evaluator = require './eval'
moment = require 'moment'

loadFactCache = {}
hasher = () -> return Array::join.call(arguments, '=-_,_-=')

loadFactBase = (account) -> (type, id) ->
	hash = hasher account, type, id
	if loadFactCache[hash]?
		result = loadFactCache[hash]
		if result.time < (new Date().getTime() - 5000)
			delete loadFactCache[hash]
		else
			return result.data

	defer = q.defer()
	new Fact_deferred_Model account, type, ->
		@load {_id: id}, (err, fact) ->

			loadFactCache[hash] =
				data: fact
				time: new Date().getTime()

			if err or not fact
				return defer.reject err or 'Not Found'

			defer.resolve fact

	return defer.promise

module.exports =

	disabled: false
	concurrency: 1
	timeout: 10000

	exec: (job, done) ->
		account = null
		accountID = job.data.account
		time = new Date parseInt job.created_at
		row = job.data.data

		if typeof accountID isnt 'string'
			if accountID._id
				accountID = accountID._id
			else
				console.log accountID
				return done 'BAD ACCOUNT ID'

		debugMode = false
		debug = () ->
			if debugMode
				console.log.apply console.log, arguments

		s = +new Date
		t = (args...) ->
			args.push (+new Date) - s
			console.log.apply console.log, args

		fns = {}
		fns.account = (next) ->
			loadAccount accountID, (err, acc) ->
				account = acc
				next err

		fns.setup = (next) ->
			account.hooks ?= Cache.create 'hooks-' + accountID, true, (key, next) ->
				account.database.collection('hooks').find().toArray next

			account.settings ?= Cache.create 'fact-settings-' + accountID, true, (key, next) ->
				account.database.collection('fact_settings').find().toArray next

			account.conditions ?= Cache.create 'fact-conditions-' + accountID, true, (key, next) ->
				account.database.collection('conditions').find().toArray next

			account.actions ?= Cache.create 'actions-' + accountID, true, (key, next) ->
				account.database.collection('actions').find().toArray next

			next()

		fns.hooks = (next) -> account.hooks.get (e, r) -> next e, r
		fns.settings = (next) -> account.settings.get (e, r) -> next e, r
		fns.conditions = (next) -> account.conditions.get (e, r) -> next e, r
		fns.actions = (next) -> account.actions.get (e, r) -> next e, r

		fns.fact = (next) ->
			new Fact_deferred_Model account, row.fact_type, () ->
				model = @
				@load {_id: row.fact_id}, true, (err, fact = {}) ->
					if err or not fact._id
						return next err or 'Bad ID'

					debugMode = debugMode or fact.data.debug is true

					# if the fact was updated, bail early - a later fact update should pick it up
					if not fact._updated
						return next 'No timestamp'

					if row.version and fact._updated.toJSON() isnt row.version
						job.log "Skipped due to invalid version"
						return next "Invalid version"

					# @addShim () =>
					next null, model

		async.series fns, (err, results) =>
			# need to do the following:
			#  - evaluate fact fields.
			#  - evaluate condition fields
			#  - send hooks.
			filter = (obj) -> row.fact_type is obj.fact_type

			hooks      = results.hooks.filter filter
			conditions = results.conditions.filter filter
			actions    = results.actions.filter filter
			settings   = results.settings.filter((setting) -> setting._id is row.fact_type).pop()
			fact       = results.fact

			if err
				if err is 'Invalid version'
					err = null
				return done err

			if not fact?.data?
				return done 'Invalid fact'

			if not settings and conditions.length is 0
				return done 'No settings or conditions for this type'

			settings.field_modes ?= {}
			settings.foreign_keys ?= {}

			context =
				http: http
				q: q
				moment: moment
				fact: fact.data
				debug: debug
				url: (value, key = 'href') -> require('url').parse(value, true)[key]
				load: loadFactBase(account)

			# evaluate fact data...
			evals = ({key: key, settings: props} for key, props of settings.field_modes when props.eval)
			evaluate = (obj, next) ->
				evaluator fact, obj.key, obj.settings, context, next

			doConditions = (condition, next) ->
				fact.evaluateCondition condition, context, (err, result) ->
					result = not err and result.every Boolean
					next null, {key: '_conditions.' + condition.condition_id, value: result, mode: 'set'}

			async.mapSeries evals, evaluate, (err, cols1) ->
				# unwrap these incase the eval returns an array of columns!
				cols1 = [].concat.apply [], cols1
				async.mapSeries conditions, doConditions, (err, cols2) ->
					columns = cols1.concat(cols2).filter Boolean

					# if we evaluated anytihng, save the fact.
					time = new Date

					if columns.length > 0
						set = $set: {}

						for column in columns
							mode = '$' + (column.mode or 'set')
							set[mode] ?= {}
							set[mode][column.key] = column.value

						set.$set._updated = time

						fact.table.update {_id: fact.data._id}, set, (err) ->
							if err
								console.error 'Fact Update write failure', fact.table.db.databaseName, fact.table.collectionName, fact.data._id, arguments

					# send hooks...
					list = hooks.map (hook) ->
						jobs.create 'hook_send', {
							title: "#{hook.hook_id} - #{row.fact_type} - #{row.fact_id}"
							account: accountID,
							data:
								hook_id: hook.hook_id,
								fact_type: hook.fact_type
								fact_id: fact.data._id
								version: time
						}

					# initiate any actions
					list = list.concat actions.map (action) ->
						job = jobs.create 'perform_action', {
							title: "#{action.action_id} - #{row.fact_type} - #{row.fact_id}"
							account: accountID,
							data:
								action_id: action.action_id,
								fact_type: action.fact_type,
								fact_id: fact.data._id
								version: time
								stage: -1
						}

					async.each list, ((job, next) -> job.save(next)), (err) ->
						done null, columns
