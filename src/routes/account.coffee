module.exports = (server) ->

	# create an account
	server.post {path: '/account', auth: false}, Account_Model.route, (req, res, next) ->
		req.model.create req.body, ErrorHandler next, () ->
			res.send {
				status: 'ok',
				statusText: 'The account has been created',
				account: req.model.export()
			}

	server.post '/account/setup', (req, res, next) ->
		req.account.setup()
		next res.send {
			status: 'ok'
			statusText: 'You know what you did.'
		}

	# show the account for this public/private keypair
	# TODO: limit keys to children of this req.key
	server.get '/account', (req, res, next) ->
		if not req.account
			return next res.notFound 'account'
		next res.send req.account.export req.key

	# update the contact info for this account.
	server.post '/account/contact', (req, res, next) ->
		req.account.setContact req.body, ErrorHandler next, () ->
			res.send {
				status: 'ok',
				statusText: 'The account contact information was updated.',
				account: req.account.export req.key
			}

	# generate a key with this name, and parent being either the current key or req.params.parent
	server.post '/account/key/:key-name', (req, res, next) ->
		keyname = req.params['key-name']
		req.body.parent ?= req.account.data.keys[keyname]?.parent or req.key.name

		if req.account.data.keys[keyname]? and not req.body.refresh?
			# only update "parent" to one we own.
			if parent = req.body.parent
				children = req.account.getChildKeys req.key.name
				for key in children when key.name is parent
					updated = true
					req.account.data.keys[keyname].parent = parent

			# only update endpoints if the updated key is a child of the authorised key.
			if endpoints = req.body.endpoints
				# ensure that the endpoints are valid regular expressions...
				for i, regex of endpoints
					endpoints[i] = regex = regex.replace /\//g, '\\/'
					reg = new RegExp regex

				children = req.account.getChildKeys req.key.name, false
				for key in children when key.name is keyname
					updated = true
					req.account.data.keys[keyname].endpoints = endpoints

			req.account.data.keys[keyname].secure = !! (req.body.secure ? true)
			req.account.save ErrorHandler next, (err) ->
				res.send {
					status: 'ok',
					statusText: 'The key was updated.',
					key: req.account.data.keys[keyname]
				}

		else
			req.account.generateKey keyname, req.body, ErrorHandler next, (err, key) ->
				res.send {
					status: 'ok',
					statusText: 'A new key with that key-name has been generated.',
					key: key
				}

	# delete a key by this name.
	server.del '/account/key/:key-name', (req, res, next) ->
		children = req.account.getChildKeys req.key.name
		for key in children when key.name is req.params['key-name']
			return req.account.deleteKey req.params['key-name'], ErrorHandler next, (err, removed) ->
				res.send {
					status: 'ok',
					statusText: 'The key and its children were removed'
					keys: (key.name for key in removed)
				}

		next 'The named key could not be deleted - either it does not exist or is not a child of the authorised key.'
