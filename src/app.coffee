fs = require 'fs'
restify = require 'restify'
crypto = require 'crypto'
check = require('validator').check

global.config = {}
global.config.port = 9876
global.mongodb = require './db'

server = restify.createServer()

# handle errors that are produced by Exceptions.
# this makes it easier to produce errors in routes.
server.on 'uncaughtException', (req, res, route, err) ->
	if err.stack and err.name not in ['ValidatorError']
		console.error err.stack
	res.send 500, {
		status: "error",
		statusText: err.message or err
	}
server.on 'NotFound', (req, res, next) -> res.send 404, status: 'error', statusText: 'Endpoint not found'
server.on 'MethodNotAllowed', (req, res, next) -> res.send 404, status: 'error', statusText: 'Endpoint not found'
server.on 'VersionNotAllowed', (req, res, next) -> res.send 404, status: 'error', statusText: 'Endpoint not found'

# parse the query string and JSON-body automatically
server.use restify.queryParser()
server.use (req, res, next) -> next null, req.headers['content-type'] = 'application/json'
server.use restify.bodyParser mapParams: false

# handle authorised routes.
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

	if req.route.auth is false
		return next()

	check(req.query.key, {
		notNull: 'This route is authorised, but no public key has been provided in the query string.',
		regex: 'The public key provided is not a 32-character hexadecimal string.'
	}).notNull().is(/[a-f0-9]{32}/i)

	check(req.query.hash, {
		notNull: 'This route is authorised, but no request hash has been provided in the query string.',
		regex: 'The HMAC hash provided is not a SHA-256 64-character hexadecimal string.'
	}).notNull().is(/[a-f0-9]{64}/i)

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
				if not err and loaded
					#2
					for name, key of @data.keys when key.public is req.query.key
						#3
						req.path = req.url.split('?').shift()
						hash_parts = []
						hash_parts.push req.path
						hash_parts.push JSON.stringify req.body or {}
						hash_parts.push key.private

						hash = crypto.createHash('sha256').update(hash_parts.join('')).digest('hex')

						if hash is req.query.hash
							req.key = key
							req.account = @
							delete req.params.key
							delete req.params.hash

							# key.endpoint regular-expression limiting.
							text = req.method.toUpperCase() + ' ' + req.path
							while key.parent
								for regex in key.endpoints or []
									reg = new RegExp '^' + regex
									if not reg.test text
										throw "Request is not allowed using this key: failed on regex '#{regex}' against '#{text}'"
								key = req.account.data.keys[key.parent] or {parent: null}

							return next()

						throw "Request signature did not match. (path = #{hash_parts[0]}, body = #{hash_parts[1]}"

				throw 'Unrecognised public key.'
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
server.listen config.port
