Q = require 'q'
request = require 'request'


deferredRequest = (method, url, body) ->
	defer = Q.defer()

	options =
		method: method.toUpperCase()
		uri: url,
		json: body

	request[method.toLowerCase()] options, (err, response, body) ->
		if err or response.statusCode.toString().charAt(0) isnt '2'
			return defer.reject err or 'Uknown error'
		defer.resolve body

	return defer.promise

module.exports =
	get: (url, body) -> return deferredRequest 'get', url, body
	post: (url, body) -> return deferredRequest 'post', url, body
	put: (url, body) -> return deferredRequest 'put', url, body
	patch: (url, body) -> return deferredRequest 'patch', url, body
	delete: (url, body) -> return deferredRequest 'delete', url, body
