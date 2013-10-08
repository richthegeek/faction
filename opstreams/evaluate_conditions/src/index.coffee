module.exports = (stream, config, row) ->

	async = require 'async'
	contextify = require 'contextify'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	Fact_Model = require models + 'fact'

	bindFunctionsPath = path.resolve lib, '../opstreams/info_mapper/lib/bind_functions'
	bindFunctions = require(bindFunctionsPath)(stream, config, row)

	config.models =
		account: Account_Model
		fact: Fact_Model

	return (row, callback) ->
		self = @

		fns = []

		if not @accountModel?
			fns.push (next) ->
				new Account_Model () ->
					self.accountModel = @
					@load {_id: stream.db.databaseName.replace(/^faction_account_/,'')}, next

		fns.push () ->
			next = Array::pop.call(arguments)
			account = self.accountModel
			self.cache ?= Cache.create 'conditions-' + account.data._id, true, (key, next) ->
				stream.db.collection('conditions').find().toArray(next)

			self.cache.get (err, conditions) ->
				next err, account, conditions

		fns.push (account, conditions, skip..., next) ->
			new Fact_Model account, row.type, () ->
				self.table = @table
				@load {_id: row.id}, (err, fact) ->
					next err, account, conditions, fact

		return async.waterfall fns, (err, account, conditions, fact) =>
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
			sandbox = {
				fact: bindFunctions(fact),
				condition: null,
				console: console
			}
			contextify(sandbox)

			for condition in conditions when condition.fact_type is row.type
				sandbox.condition = condition
				sandbox.run code

				result['_conditions.' + condition.condition_id] = !! sandbox.condition.result

			# update the original fact with these condition values
			self.table.update {_id: row.id}, {$set: result}, (err) =>
				# and create a "fact_evaluated" for actions to listen for...
				callback err, {
					id: row.id,
					type: row.type,
					result: result,
					time: +new Date
				}
