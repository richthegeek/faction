async = require 'async'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class Action_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'actions', (self, db, coll) ->
			callback.apply @, arguments

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new Action_Model req.account, () ->
			req.model = @
			next()

	validate: (data, callback) ->
		if not data.conditions
			throw 'An action must have a map of conditions determining wether it is run.'

		data.perform_once_per_fact ?= false

		if not Array.isArray(data.actions) or data.actions.length is 0
			throw 'An action must have an array of at least 1 action to perform.'

		for action in data.actions when not action or not action.action
			throw 'All actions must be an object with an "action" property.'

		@actionTypes (err, types) ->
			iterator = (action, next) ->
				if not type = types[action.action]
					throw "Unknown action '#{action.action}'. GET /action-types to see a valid list."

				type.validate action, (err) ->
					if err then return next "Action '#{action.action}' could not validate: #{err}"
					next()

			async.each data.actions, iterator, callback


	export: () ->
		data = super
		return {
			action_id: data.action_id,
			fact_type: data.fact_type,
			actions: data.actions,
			conditions: data.conditions,
			perform_once_per_fact: !! data.perform_once_per_fact
		}

	fact_is_runnable: (factObj) ->
		data = @export()
		fact = factObj.export()

		for condition, val of data.conditions
			if fact._conditions[condition] isnt val
				return false

		return true

	fact_run: (factObj, stage, callback) ->
		if typeof stage is 'function'
			callback = stage
			stage = 0

		if typeof Number(stage) isnt 'number'
			stage = 0

		if stage is 0
			if not @fact_is_runnable factObj
				return callback null, false

		@actionTypes (err, types) =>
			runner = (action, next) =>
				if type = types[action.action]
					type.exec action, factObj.export(), next

			async.mapSeries @data.actions.slice(stage), runner, callback


	actionTypes: (callback) ->
		cache = Cache.create 'action-types', true, (key, next) =>
			fs = require 'fs'
			path = require 'path'
			dir = path.resolve __dirname, '../actions'
			types = {}
			for file in fs.readdirSync(dir) when file.substr(-3) is '.js'
				name = file.slice 0, -3
				object = require dir + '/' + file
				types[object.name] = object
			next null, types

		cache.get callback

	setup: () ->
		@db.addStreamOperation {
			_id: 'action_eval',
			sourceCollection: 'fact_evaluated',
			targetCollection: 'action_results',
			type: 'untracked',
			operations: [{operation: 'perform_action'}],
		}

		@db.addStreamOperationType 'perform_action', {
			dependencies: {
				'cache': 'shared-cache',
				'async': 'async',
				'fact': __dirname + '/fact',
				'action': __dirname + '/action'
			},
			account: {
				_id: @account.data._id,
				databaseName: @account.dbname()
			},
			exec: (row, callback) ->
				cache = @modules.cache.create 'actions-' + @account, true, (key, next) =>
					@stream.db.collection('actions').find().toArray(next)

				modules = @modules

				account = @account
				account.dbname = () -> account.databaseName

				new modules.fact account, row.type, (self) ->
					@load {_id: row.id}, (err) ->
						fact = @

						iterator = (action, next) ->
							if action.fact_type != fact.type
								return next()

							new modules.action account, (err) ->
								@import action, () ->
									action = @

									@fact_run fact, row.stage or 0, (err, result) ->
										next err, result and {
											action_id: action.data.action_id,
											fact_type: action.data.fact_type,
											fact_id: row.id,
											time: new Date,
											result: err or result,
											status: (err and 'error' or 'ok')
										}

						cache.get (err, actions) ->
							modules.async.map actions, iterator, (err, rows) ->
								callback null, rows

		}
