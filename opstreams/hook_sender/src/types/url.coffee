module.exports =
	exec: (hook, fact, cb) ->

		console.log 'URL', hook, fact
		return

		options =
			method: 'POST'
			uri: hook.url,
			json: fact

		# try send the data...
		request.post options, cb
