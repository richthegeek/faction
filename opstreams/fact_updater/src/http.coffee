Q = require 'q'
request = require 'request'

init = request.Request::init
request.Request::init = (options) ->
	defer = Q.defer()
	@on 'complete', defer.resolve
	@on 'error', defer.reject

	# copy over promise functions, except timeout.
	for key, val of defer.promise when key isnt 'timeout'
		@[key] ?= defer.promise[key]

	init.call @, options

module.exports = request
