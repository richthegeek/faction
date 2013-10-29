request = require 'request'
module.exports =
	exec: (hook, fact, cb) ->

		options =
			method: hook.options.method or 'POST'
			uri: hook.options.url,
			json: fact

		# try send the data...
		request.post options, (err, req, body) ->
			cb err, body
