module.exports =
	exec: (hook, fact, cb) ->

		options =
			method: 'POST'
			uri: hook.url,
			json: fact

		# try send the data...
		request.post options, cb
