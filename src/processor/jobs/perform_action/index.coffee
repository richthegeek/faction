async = require 'async'
Cache = require 'shared-cache'

module.exports = (job, done) ->
	account = null
	accountID = job.data.account
	time = new Date parseInt job.created_at
	row = job.data.data

	fns = {}
	fns.account = (next) ->
		loadAccount accountID, (err, acc) ->
			account = acc
			next err

	fns.setup = (next) ->
		account.actions ?= Cache.create 'actions-' + accountID, true, (key, next) ->
			account.database.collection('actions').find().toArray next
		next()

	fns.actions = (next) -> account.actions.get (e, r) -> next e, r
	fns.actionTypes = (next) -> Action_Model.actionTypes (e, r) -> next e, r

	fns.fact = (next) ->
		new Fact_deferred_Model account, row.fact_type, () ->
			model = @
			@load {_id: row.fact_id}, true, (err, fact = {}) ->
				if err or not fact._id
					return next err or 'Bad ID'

				# if the fact was updated, bail early - a later fact update should pick it up
				if fact._updated.toJSON() isnt row.version
					return next "Invalid version"

				@addShim () =>
					next null, model

	async.series fns, (err, results) =>
		if err
			console.error err
			return done err


		# need to do the following:
		#  - if we are at stage -1
		#    - check that the fact actually matches these conditions
		#  - skip to action[stage + 1]
		#  - for each action, perform the action
		filter = (obj) -> row.fact_type is obj.fact_type

		actions = results.actions.filter filter
		fact = results.fact
		types = results.actionTypes

		action = actions.filter(filter).filter((action) -> action.action_id is row.action_id).pop()

		if action.length is 0
			return done 'No such action'

		fact.data._conditions ?= {}

		if row.stage < 0 or not row.stage?
			for condition, value of action.conditions
				fact_val = !! fact.data._conditions[condition]
				if value isnt fact_val
					return done 'Did not match'

		stage = row.stage
		iterate = (action, next) ->
			stage = stage + 1

			if not type = types[action.action]
				return next 'No such type'

			obj = {
				job: job.data
				action: action,
				step: action,
				stage: stage,
				fact: fact
			}

			type.validate obj, (err) ->
				if err
					return next err, action

				type.exec obj, next

		actions = action.actions.slice row.stage + 1
		async.mapSeries actions, iterate, (err, result) ->
			if err and err.halt
				return done null, 'Delayed on stage', (row.stage + result.length)

			done err


