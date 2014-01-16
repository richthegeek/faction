check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class Info_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	create: (type, info, log, callback) ->
		log 1
		if typeof info is 'function'
			callback = info
			info = {}

		log 2
		delete info._id
		info._type = type

		log 3
		job = jobs.create('info', {
			title: "#{@account.data._id } - #{new Date}"
			account: @account.data._id
			data: info
		})

		log 4
		job.save (err) ->
			log 5
			callback err, job

	@route = (req, res, next) ->
		new Info_Model req.account, () ->
			req.model = @
			next()
