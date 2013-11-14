http = require('./http')
q = require 'q'
async = require 'async'
Cache = require 'shared-cache'

module.exports = (job, done) ->

	# store is an object with which we can delete all entries at the end for GC purposes
	store = {}

	accountID = job.data.account
	time = new Date parseInt job.created_at
	row = job.data.data

	s = +new Date
	t = (args...) ->
		args.push (+new Date) - s
		console.log.apply console.log, args

	fns = {}
	fns.account = (next) ->
		loadAccount accountID, (err, acc) ->
			store.account = acc
			next err

	fns.setup = (next) ->
		store.account.hooks ?= Cache.create 'hooks-' + accountID, true, (key, next) ->
			store.account.database.collection('hooks').find().toArray next

		store.account.settings ?= Cache.create 'fact-settings-' + accountID, true, (key, next) ->
			store.account.database.collection('fact_settings').find().toArray next

		store.account.conditions ?= Cache.create 'fact-conditions-' + accountID, true, (key, next) ->
			store.account.database.collection('conditions').find().toArray next

		store.account.actions ?= Cache.create 'actions-' + accountID, true, (key, next) ->
			store.account.database.collection('actions').find().toArray next

		next()

	fns.hooks = (next) -> store.account.hooks.get (e, r) -> next e, r
	fns.settings = (next) -> store.account.settings.get (e, r) -> next e, r
	fns.conditions = (next) -> store.account.conditions.get (e, r) -> next e, r
	fns.actions = (next) -> store.account.actions.get (e, r) -> next e, r

	fns.fact = (next) ->
		new Fact_deferred_Model store.account, row.fact_type, () ->
			model = @
			@load {_id: row.fact_id}, true, (err, fact = {}) ->
				if err or not fact._id
					return next err or 'Bad ID'

				# if the fact was updated, bail early - a later fact update should pick it up
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
		settings   = results.settings.filter((setting) -> setting._id is row.fact_type).pop() or {}

		settings.field_modes ?= {}
		settings.foreign_keys ?= {}

		fact = results.fact

		if err
			# supress this "error"
			if err is 'Invalid version'
				return done()
			return done err

		if not fact?.data?
			return done 'Invalid fact'

		context =
			http: http
			q: q
			fact: fact.data,
			load: (type, id) ->
				defer = require('q').defer()
				new Fact_deferred_Model store.account, type, () ->
					@load {_id: id}, (err, found) ->
						if err or not found
							return defer.reject err or 'Not found'
						defer.resolve @data
				return defer.promise

		# evaluate fact data...
		evals = ([key, props] for key, props of settings.field_modes when props.eval)
		evaluate = (arr, next) ->
			[key, props] = arr
			# evaluate the value

			# context = getContext fact
			fact.withMap [], props.map, context, (err, map) =>
				map[k] = v for k, v of context
				fact.data.eval props.eval, map, (err, result) =>
					result = result ? props.default ? null

					fact.data.set.call fact.data.data, key, result
					next null, {key: key, value: result}

		doConditions = (condition, next) ->
			fact.evaluateCondition condition, context, (err, result) ->
				result = not err and result.every Boolean
				next null, {key: '_conditions.' + condition.condition_id, value: result}

		async.mapSeries evals, evaluate, (err, cols1) ->
			async.mapSeries conditions, doConditions, (err, cols2) ->
				columns = cols1.concat(cols2).filter Boolean

				# if we evaluated anytihng, save the fact.
				time = new Date

				if columns.length > 0
					set = {}
					set[col.key] = col.value for col in columns
					set._updated = time

					fact.table.update {_id: fact.data._id}, {$set: set}, -> null

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

					account = null

					done null, columns

module.exports.concurrency = 1
module.exports.timeout = 10000
