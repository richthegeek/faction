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

		job = jobs.create('info', {
			title: "#{@account.data._id } - #{new Date}"
			account: @account.data._id
			data: info
		})

		job.save (err) -> callback err, job

	@route = (req, res, next) ->
		new Info_Model req.account, () ->
			req.model = @
			next()
