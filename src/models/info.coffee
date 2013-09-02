check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class Info extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info', callback

	create: (type, info, callback) ->
		if typeof info is 'function'
			callback = info
			info = {}

		delete info._id
		info._type = type
		@table.insert info, callback
