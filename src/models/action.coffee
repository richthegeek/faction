async = require 'async'
Model = require './model'
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

	validate: (data) ->
		if not data.conditions
			throw 'An action must have a map of conditions determining wether it is run.'

		data.perform_once_per_fact ?= false

		if not Array.isArray(data.actions) or data.actions.length is 0
			throw 'An action must have an array of at least 1 action to perform.'

		for action in data.actions when not action or not action.action
			throw 'All actions must be an object with an "action" property.'

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

	fact_run: (factObj, callback) ->
		callback null, 42
