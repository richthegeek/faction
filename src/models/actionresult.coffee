check = require('validator').check
crypto = require 'crypto'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class ActionResult_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'action_results', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new ActionResult_Model req.account, () ->
			req.model = @
			next()

	setup: () ->
		@table.ensureIndex {fact_type: 1, fact_id: 1, action_id: 1}, {}, () -> null

	validate: (data, callback) ->
		callback()

	export: () ->
		return {
			fact_id: @data.fact_id,
			time: @data.time,
			status: @data.status,
			result: @data.result
		}
