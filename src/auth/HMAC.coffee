module.exports = (req, res, next) ->
	if req.route.auth not in [null, undefined, 'hmac', 'HMAC']
		return next()

	if not req.query.key or not req.query.key.toString().match /^[a-f0-9]{32}/i
		return next new restify.InvalidCredentialsError 'This route is authorised, but no public key has been provided in the query string.'

	# steps to authorise:
	# 1: load account by querying for when public_base is the same as req.query.key[0..16]
	# 2: check for a key in that account where public is the same as req.query.key
	# 3: create HMAC using that key's private value
	# 4: compare and authorise if they are the same.
	new Account_Model () ->
		id = req.query.key.substring(0, 16)
		#1
		@load {_id: id}, (err, loaded) ->
			key = (key for name, key of (@data.keys or {}) when key.public is req.query.key).pop()

			if err or not loaded or not key
				return next new restify.InvalidCredentialsError 'Unrecognised public key.'

			if key.secure and not req.query.hash or not req.query.hash.toString().match /^[a-f0-9]{64}/i
				return next new restify.InvalidCredentialsError 'This route is authorised, but no request hash been provided in the query string.'

			req.path = req.url.split('?').shift()

			hash_parts = [
				req.path,
				JSON.stringify(req.body or {})
				key.private
			]
			hash = require('crypto').createHash('sha256').update(hash_parts.join('')).digest('hex')

			if key.secure and hash isnt req.query.hash
				return next new restify.InvalidCredentialsError "Request signature did not match. (path = #{hash_parts[0]}, body = #{hash_parts[1]}"

			if key.secure is false
				console.log 'Bypassing security'

			req.key = key
			req.account = @
			delete req.params.key
			delete req.params.hash

			# key.endpoint regular-expression limiting.
			text = req.method.toUpperCase() + ' ' + req.path
			while key.parent
				key.endpoints = [].concat key.endpoints
				# if no endpoints match, and the endpoints are longer than one
				if key.endpoints.length > 0 and (1 for regex in key.endpoints when new RegExp('^' + regex).test(text)).length is 0
					return next restify.InvalidCredentialsError "Request is not allowed using this key due to endpoint restriction."
				key = req.account.data.keys[key.parent] or {parent: null}
			return next()
