async = require 'async'
path = require 'path'
request = require 'request'
Cache = require 'shared-cache'

module.exports =

	disabled: true
	concurrency: 1

	exec: (job, done) ->
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
			account.hooks ?= Cache.create 'hooks-' + accountID, true, (key, next) ->
				account.database.collection('hooks').find().toArray next

			next()

		fns.hooks = (next) -> account.hooks.get (e, r) -> next e, r

		fns.fact = (next) ->
			new Fact_deferred_Model account, row.fact_type, () ->
				model = @
				@load {_id: row.fact_id}, true, (err, fact = {}) ->
					if err or not fact._id
						return next err or 'Bad ID'

					# if the fact was updated, bail early - a later fact update should pick it up
					if fact._updated.toJSON() isnt row.version
						job.log("Skipped due to invalid version")
						return next "Invalid version"

					@addShim () =>
						next null, model

		async.series fns, (err, results) =>
			if err
				return done err

			hook = results.hooks.filter((hook) -> hook.fact_type is row.fact_type and hook.hook_id is row.hook_id).pop()

			if not hook
				return done 'Unknown hook'

			if not results.fact
				console.log 'No fact?', accountID, typeof row.fact_id, row.fact_id, row.fact_type
				return done 'Unknown fact'

			try
				results.fact.withMap hook.with, hook.map, false, (err, result) ->
					# double-JSON to strip getters at this stage
					fact = JSON.parse JSON.stringify result

					# todo: handle failures, re-send, etc...
					cb = (err, res, body) ->
						# if res.statusCode.toString().charAt(0) is '2'
						return callback null, {
							hook_id: row.hook_id,
							fact_type: row.fact_type,
							fact_id: fact._id,
							status: res.statusCode,
							body: body,
							time: new Date
						}

					hook.type ?= 'url'
					# TODO: make this way more clever
					file = path.resolve(__dirname, './types') + '/' + hook.type
					hookService = require file


					hookService.exec hook, fact, (err, result) ->
						if err
							console.log JSON.stringify err
							return done err

						done err, result

			catch err
				console.log 'Shit code alert'
				console.log err.stack or err.message or err
				console.log typeof err
				console.log (err.then? and 'Promise') or (Object::toString.call(err))
				return
