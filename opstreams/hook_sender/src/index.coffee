module.exports = (stream, config, row) ->

	request = require 'request'
	async = require 'async'
	Cache = require 'shared-cache'

	path = require 'path'
	lib = path.resolve __dirname, '../../../lib'
	models = lib + '/models/'

	Account_Model = require models + 'account'
	Fact_Model = require models + 'fact_deferred' # change back to fact later
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

			if hook.mode is 'snapshot'
				new Fact_Model account, row.fact_type, () ->
					hook.with = [].concat.call [], hook.with ? []

					hook.path ?= 'this'
					if 'this' isnt hook.path.substring 0, 4
						hook.path = 'this.' + hook.path

					self.table = @table
					@load {_id: row.fact_id}, (err, found) ->
						if err or not found
							return callback 'Fact not found'

						@withMap hook.with, hook.map, false, (err, result) ->
							# double-JSON to strip getters at this stage
							next err, account, hook, JSON.parse JSON.stringify result

			else
				next err, account, hook, row.data

		return async.waterfall fns, (err, account, hook, fact) =>
			if err then return callback err
			if not fact then return callback()

			# verify the fact has not been updated.
			expired = hook.mode isnt 'snapshot' and row.data._updated isnt fact._updated
			if expired
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

			hook.type ?= 'url'
			# TODO: make this way more clever
			file = path.resolve(__dirname, './types') + '/' + hook.type
			hookService = require file

			try
				hookService.exec hook, fact, (err, result) ->
					if err
						console.log err
						console.log JSON.stringify err
						throw err

					cb err, result
			catch err
				console.log 'Shit code alert'
				console.log err
				return
