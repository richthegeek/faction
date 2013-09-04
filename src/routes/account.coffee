module.exports = (server) ->

	# create an account
	server.post {path: '/account', auth: false}, Account_Model.route, (req, res, next) ->
		req.model.create req.body, (err) ->
			res.send {
				status: 'ok',
				statusText: 'The account has been created',
				account: account.export()
			}

	# show the account for this public/private keypair
	# TODO: limit keys to children of this req.key
	server.get '/account', (req, res, next) ->
		res.send req.account.export req.key

	# update the contact info for this account.
	server.post '/account/contact', (req, res, next) ->
		req.account.setContact req.body, (err) ->
			res.send {
				status: 'ok',
				statusText: 'The account contact information was updated.',
				account: req.account.export req.key
			}

	# generate a key with this name, and parent being either the current key or req.params.parent
	server.post '/account/key/:key-name', (req, res, next) ->
		req.params.parent ?= req.key.name
		req.account.generateKey req.params['key-name'], req.params.parent, (err, key) ->
			res.send {
				status: 'ok',
				statusText: 'A new key with that key-name has been generated.',
				key: key
			}

	# delete a key by this name.
	server.del '/account/key/:key-name', (req, res, next) ->
		children = req.account.getChildKeys req.key.name
		for key in children when key.name is req.params['key-name']
			return req.account.deleteKey req.params['key-name'], (err, removed) ->
				res.send {
					status: 'ok',
					statusText: 'The key and its children were removed'
					keys: (key.name for key in removed)
				}

		throw 'The named key could not be deleted - either it does not exist or is not a child of the authorised key.'
