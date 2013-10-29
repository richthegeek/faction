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
			index = stage
			runner = (action, next) =>
				if type = types[action.action]
					info = {
						step: action,
						action: @export()
						fact: factObj.export(),
						fact_type: factObj.type,
						account: @account,
						stage: index++
					}
					type.exec info, (err, res, broke = false) ->
						if err then next 'err', err
						else if broke then next 'break', res
						else next null, res

			async.mapSeries @data.actions.slice(stage), runner, (e, r) ->
				if e is 'err'
					e = r
					r = null
				if e is 'break'
					e = null
				callback e, r, index - 1


	@actionTypes = @::actionTypes = (callback) ->
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
		path = require 'path'
		@db.addStreamOperation {
			_id: 'action_eval',
			sourceCollection: 'fact_evaluated',
			targetCollection: 'action_results',
			type: 'untracked',
			operations: [{
				modular: true
				operation: path.resolve(__dirname, '../../opstreams/perform_action')
			}],
		}
