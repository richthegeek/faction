module.exports = (stream, config, row) ->

	async = require 'async'
	contextify = require 'contextify'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	Fact_Model = require models + 'fact'

	account_name = stream.db.databaseName.replace(/^faction_account_/,'')

	_conditions = Cache.create 'fact-conditions-' + account_name, true, (key, next) ->
		stream.db.collection('fact_conditions').find().toArray next

	_hooks = Cache.create 'hooks-' + account_name, true, (key, next) ->
		stream.db.collection('hooks').find().toArray next


	bindFunctionsPath = path.resolve lib, '../opstreams/info_mapper/lib/bind_functions'
	bindFunctions = require(bindFunctionsPath)(stream, config, row)

	config.models =
		account: Account_Model
		fact: Fact_Model

	return (row, callback) ->
		self = @
		fns = {}

		if not row.type
			return callback()

		fns.account = (next) ->
			if self.accountModel
				return next null, self.accountModel

			new Account_Model () ->
				self.accountModel = @
				@load {_id: account_name}, next

		fns.conditions = (next) ->
			_conditions.get next

		fns.fact = (next) ->
			new Fact_Model self.accountModel, row.type, () ->
				if row.fact
					return @import row.fact, () -> next null, @

				@load {_id: row.id}, () -> next null, @

		return async.series fns, (err, results) =>

			if err or not results.fact
				return callback err, null

			fact = results.fact
			conditions = results.conditions.filter (cond) -> cond.fact_type is row.type

			code = """condition.result = condition.conditions.every(function(condition) {
				try {
					return eval(condition);
				} catch(e) {
					console.error(e);
					return false;
				}
			});"""

			result = {}
			sandbox = {
				fact: bindFunctions(fact),
				condition: null,
				console: console
			}
			contextify(sandbox)

			for condition in conditions
				sandbox.condition = condition
				sandbox.run code

				result['_conditions.' + condition.condition_id] = !! sandbox.condition.result

			sandbox.dispose()


			# update the original fact with these condition values
			fact.table.update {_id: row.id}, {$set: result}, (err) =>
				# and create a "fact_evaluated" for actions to listen for...
				delete row.fact
				row.result = result
				row.time = +new Date

				callback err, row
