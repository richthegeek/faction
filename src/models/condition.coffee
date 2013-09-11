console.log __dirname

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

	validate: (data) ->
		if not Array.isArray(data.conditions) or data.conditions.length is 0
			throw 'A condition must have an array of conditions to be evaluated.'

		# todo: check conditions are valid JS.

	export: () ->
		data = super
		return {
			condition_id: data.condition_id,
			fact_type: data.fact_type,
			description: data.description,
			conditions: data.conditions
		}

	setup: () ->

		@db.addStreamOperation {
			_id: 'condition_eval',
			sourceCollection: 'fact_updates',
			targetCollection: 'fact_evaluated',
			type: 'untracked',
			operations: [{operation: 'evaluate_conditions'}],
		}

		@db.addStreamOperationType 'evaluate_conditions', {
			dependencies: {
				'cache': 'shared-cache',
				'async': 'async',
				'fact': __dirname + '/fact',
				'context': 'contextify'
			},
			account: {
				_id: @account.data._id,
				db: @account.dbname()
			},
			exec: (row, callback) ->
				# row is a "change manifest" with the following keys:
				#	- type
				#	- id (not _id!)
				#	- time
				#	- changes
				cache = @modules.cache.create 'conditions-' + @account, true, (key, next) =>
					@stream.db.collection('conditions').find().toArray(next)

				fact_collection = @stream.db.collection('fact_' + row.type)
				fact_collection.findOne {_id: row.id}, (err, fact) =>
					if err then return callback err
					if not fact then return callback()

					code = """condition.result = condition.conditions.every(function(condition) {
						try {
							return eval(condition);
						} catch(e) {
							console.error(e);
							return false;
						}
					});"""

					result = {}
					cache.get (err, conditions) =>
						sandbox = {
							fact: @modules.fact.prototype.bindFunctions(fact),
							condition: null,
							console: console
						}
						@modules.context(sandbox)
						for condition in conditions when condition.fact_type is row.type
							sandbox.condition = condition
							sandbox.run code

							result[condition.condition_id] = !! sandbox.condition.result

						# update the original fact with these condition values
						fact_collection.update {_id: row.id}, {$set: _conditions: result}, (err) =>
							# and create a "fact_evaluated" for actions to listen for...
							callback err, {
								id: row.id,
								type: row.type,
								result: result,
								time: +new Date
							}
		}
