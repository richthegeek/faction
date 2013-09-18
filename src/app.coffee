fs = require 'fs'
restify = require 'restify'
crypto = require 'crypto'

global.config = {}
global.config.port = 9876
global.mongodb = require './db'

server = restify.createServer
	formatters:
		'application/json': (req, res, body) ->
			if body instanceof Error
				res.statusCode = body.statusCode or 500
				if body.body
					body = body.body
				body =
					status: 'error'
					statusText: body.message

			else if Buffer.isBuffer body
				body = body.toString 'base64'

			else if typeof body is 'string'
				body =
					status: 'error'
					statusText: body

			data = JSON.stringify body
			res.setHeader 'Content-Length', Buffer.byteLength data
			return data

global.ErrorHandler = (next, good) ->
	return (err) ->
		if err
			next new Error err
		else
			next good.apply this, arguments

global.error = (message) -> {status: 'error', statusText: message}

# handle errors that are produced by Exceptions.
# this makes it easier to produce errors in routes.
server.on 'uncaughtException', (req, res, route, err) ->
	console.error err.stack
	res.send 500, {
		status: "error",
		statusText: err.message or err
	}
server.on 'NotFound', (req, res, next) -> res.send 404, status: 'error', statusText: 'Endpoint not found'
server.on 'MethodNotAllowed', (req, res, next) -> res.send 404, status: 'error', statusText: 'Endpoint not found'
server.on 'VersionNotAllowed', (req, res, next) -> res.send 404, status: 'error', statusText: 'Endpoint not found'

# logging
server.on 'after', (req, res, route, err) ->
	time = new Date - res._time
	console.log "#{req.method} #{req.route.path} (#{time}ms): #{res.statusCode}"

# parse the query string and JSON-body automatically
server.use restify.queryParser()
server.use (req, res, next) -> next null, req.headers['content-type'] = 'application/json'
server.use restify.bodyParser mapParams: false, requestBodyOnGet: true

server.use (req, res, next) ->
	if req.method is 'GET' and req.params.body
		req.body = JSON.parse req.params.body
	next()


server.use (req, res, next) ->
	res.notFound = (noun) ->
		@send 404, {
			status: 'error',
			statusText: "Their was no #{noun} found matching those parameters"
		}

	req.throw = (err) ->
		server.emit 'uncaughtException', req, res, req.route, err

	req.params.asQuery = (allowed...) ->
		if allowed.length is 0
			allowed = (k for k, v of req.params)

		ret = {}
		for name in allowed when req.params[name]?
			val = req.params[name]
			if typeof val isnt 'function'
				name = name.replace /[^a-z0-9_]+/ig, '_'
				ret[name] = val
		return ret

	next()

# handle authorised routes.
server.use (req, res, next) ->
	if req.route.auth is false
		return next()

	if not req.query.key or not req.query.key.toString().match /^[a-f0-9]{32}$/i
		return next new restify.InvalidCredentialsError 'This route is authorised, but no public key has been provided in the query string.'

	if not req.query.hash or not req.query.hash.toString().match /^[a-f0-9]{64}$/i
		return next new restify.InvalidCredentialsError 'This route is authorised, but no request hash been provided in the query string.'

	# steps to authorise:
	# 1: load account by querying for when public_base is the same as req.query.key[0..16]
	# 2: check for a key in that account where public is the same as req.query.key
	# 3: create HMAC using that key's private value
	# 4: compare and authorise if they are the same.
	new Account_Model () ->
		id = req.query.key.substring(0, 16)
		#1
		@load {_id: id}, (err, loaded) ->
			try
				if err or not loaded
					throw 'Unrecognised public key.'

				for name, key of @data.keys when key.public is req.query.key
					req.path = req.url.split('?').shift()
					hash_parts = []
					hash_parts.push req.path
					hash_parts.push JSON.stringify req.body or {}
					hash_parts.push key.private

					hash = crypto.createHash('sha256').update(hash_parts.join('')).digest('hex')

					if (key.secure is false) or (hash is req.query.hash)
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
								throw "Request is not allowed using this key due to endpoint restriction."

							key = req.account.data.keys[key.parent] or {parent: null}

						return next()

					throw "Request signature did not match. (path = #{hash_parts[0]}, body = #{hash_parts[1]}"

			catch err
				server.emit 'uncaughtException', req, res, req.route, err

# load models and routes automatically.
files = models: {}, routes: {}
for dir of files
	for file in fs.readdirSync(__dirname + '/' + dir) when file.substr(-3) is '.js'
		name = file.slice 0, -3
		files[dir][name] = require __dirname + '/' + dir + '/' + file

for name, model of files.models
	name = name.slice(0,1).toUpperCase() + name.slice(1) + '_Model'
	global[name] = model

for group, fn of files.routes
	fn server

# listen on the configured port.
console.log 'Listening on', config.port
server.listen config.port
