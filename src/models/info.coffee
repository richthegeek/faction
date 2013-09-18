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

		info._type = type
		@table.insert info, callback

	@route = (req, res, next) ->
		new Info_Model req.account, () ->
			req.model = @
			next()
