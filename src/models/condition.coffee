async = require 'async'
Model = require './model'
module.exports = class Condition_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'conditions', (self, db, coll) ->
			callback.apply @, arguments

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new Condition_Model req.account, () ->
			req.model = @
			next()

	validate: (data, callback) ->
		if not Array.isArray(data.conditions) or data.conditions.length is 0
			throw 'A condition must have an array of conditions to be evaluated.'

		# todo: check conditions are valid JS.
		callback()

	export: () ->
		data = super
		return {
			condition_id: data.condition_id,
			fact_type: data.fact_type,
			description: data.description,
			conditions: data.conditions
		}

	setup: () ->
		path = require 'path'
		@db.addStreamOperation {
			_id: 'condition_eval',
			sourceCollection: 'fact_updates',
			targetCollection: 'fact_evaluated',
			type: 'untracked',
			operations: [{
				modular: true
				operation: path.resolve(__dirname, '../../opstreams/evaluate_conditions')
			}],
		}
