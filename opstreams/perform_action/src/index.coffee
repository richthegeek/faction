module.exports = (stream, config, row) ->

	async = require 'async'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	Action_Model = require models + 'action'
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
			self.cache ?= Cache.create 'actions-' + account.data._id, true, (key, next) ->
				stream.db.collection('actions').find().toArray(next)

			self.cache.get (err, actions) ->
				next err, account, actions

		fns.push (account, actions, skip..., next) ->
			new Fact_Model account, row.type, () ->
				self.table = @table
				@load {_id: row.id}, (err, fact) ->
					next err, account, actions, fact

		return async.waterfall fns, (err, account, actions, fact) =>
			if err then return callback err
			if not fact then return callback()

			iterator = (action, next) ->
				if action.fact_type != fact.type
					return next()

				new Action_Model account, (err) ->
					@import action, () ->
						action = @

						@fact_run fact, row.stage or 0, (err, result, final_stage) ->
							next null, {
								action_id: action.data.action_id,
								fact_type: action.data.fact_type,
								fact_id: row.id,
								time: new Date,
								result: [].concat(err or result),
								status: (err and 'error' or 'ok'),
								stage_from: Number(row.stage or 0),
								stage_to: final_stage
							}

			modules.async.map actions, iterator, (err, rows) ->
				callback null, rows
