check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class Info_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	create: (type, info, callback) ->
		if typeof info is 'function'
			callback = info
			info = {}

		delete info._id
		info._type = type

		job = {
			title: "#{@account.data._id } - #{new Date}"
			account: @account.data._id
			data: info
		}

		jobs.create('info', job).save callback

		# TODO: stop inserting if it works!
		@table.insert info, () -> null #callback

	@route = (req, res, next) ->
		new Info_Model req.account, () ->
			req.model = @
			next()
