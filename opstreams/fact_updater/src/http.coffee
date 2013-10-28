Q = require 'q'
request = require 'request'

init = request.Request::init
request.Request::init = (options) ->
	defer = Q.defer()
	@on 'complete', (req) -> defer.resolve req.body
	@on 'error', defer.reject

	# ensure we have a callback, or request doesnt parse returned data
	@callback ?= -> null

	# copy over promise functions, except timeout.
	for key, val of defer.promise when key isnt 'timeout'
		@[key] ?= defer.promise[key]

	init.call @, options

module.exports = request
