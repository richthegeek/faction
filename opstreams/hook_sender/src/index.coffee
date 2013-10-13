module.exports = (stream, config, row) ->

	request = require 'request'
	async = require 'async'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	Fact_Model = require models + 'fact'
	config.models = account: Account_Model

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

			self.cache ?= Cache.create 'hooks-' + account.data._id, true, (key, next) ->
				stream.db.collection('hooks').find().toArray(next)

			self.cache.get (err, hooks) ->
				for hook in hooks
					if hook.fact_type is row.fact_type and hook.hook_id is row.hook_id
						return next null, account, hook

				# todo; delete all things using this ID at this stage?
				next 'Unknown hook id'

		fns.push (account, hook, skip..., next) ->
			new Fact_Model account, row.fact_type, () ->
				self.table = @table
				@table.findOne {_id: row.data._id}, (err, fact) ->
					next err, account, hook, fact

		return async.waterfall fns, (err, account, hook, fact) =>
			if err then return callback err
			if not fact then return callback()

			# verify the fact has not been updated.
			if row.data._updated isnt fact._updated
				console.log 'Expired'
				return next()

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

			options =
				method: 'POST'
				uri: hook.url,
				json: row.data

			# try send the data...
			request.post options, cb
