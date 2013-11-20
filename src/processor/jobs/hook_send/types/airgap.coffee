request = require 'request'
module.exports =
	exec: (hook, fact, cb) ->

		console.log (k for k of fact), fact.hook

		options =
			method: hook.options.method or 'POST'
			uri: "t.trakapo.com:2474/#{hook.options.subtype}/exec"
			json: fact

		# try send the data...
		request.post options, (err, req, body) ->
			cb err, body
