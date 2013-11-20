request = require 'request'
module.exports =
	exec: (hook, fact, cb) ->

		options =
			method: hook.options.method or 'POST'
			uri: "http://t.trakapo.com:2474/#{hook.options.subtype}/exec"
			json: fact

		# try send the data...
		request.post options, (err, req, body) ->
			cb err, body
