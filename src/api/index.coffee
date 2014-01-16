global.restify = require 'restify'

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
			res.bodyData = data
			res.setHeader 'Content-Length', Buffer.byteLength data
			return data

# error handler, used by plenty of things
global.ErrorHandler = (next, good) -> (err) ->
	if err
		return next new Error err
	next good.apply this, arguments

# handle errors that are produced by Exceptions.
# this makes it easier to produce errors in routes.
server.on 'uncaughtException', (req, res, route, err) ->
	# console.error err.stack
	res.send 500, {
		status: "error",
		statusText: err.message or err
	}

server.on 'NotFound', (req, res, next) -> next res.send 404, status: 'error', statusText: 'Endpoint not found'
server.on 'MethodNotAllowed', (req, res, next) -> next res.send 404, status: 'error', statusText: 'Endpoint not found'
server.on 'VersionNotAllowed', (req, res, next) -> next res.send 404, status: 'error', statusText: 'Endpoint not found'

# logging
server.on 'after', (req, res, route, err) ->
	if req.suppressLog or res.suppressLog
		return

	time = new Date - res._time
	req.route ?= {}
	req.route.path ?= req._path ? '/'
	res.logMessage ?= ''
	console.log "#{req.method} #{req.route.path} (#{time}ms): #{res.statusCode} #{res.logMessage}"

	nice_path = req.route.path.slice(1).replace /[^a-z0-9_]+/g, '_'
	if nice_path is ''
		nice_path = 'frontpage'

	# stats.increment 'api.requests', 1
	# stats.timing 'api.response', time
	# stats.timing "api.response.#{req.method.toLowerCase()}.#{nice_path}", time

	if res.statusCode.toString().slice(0,1) isnt '2'
		# stats.increment 'api.errors', 1
		if 0 > res.bodyData.indexOf '"Endpoint not found"'
			console.error res.bodyData


# CORS
server.use restify.CORS()
server.use restify.fullResponse()

# time logging
server.use (req, res, next) ->
	req.canary = true
	req.tempID = (Math.round Math.random() * 99999).toString()
	req.logTime = req.logTime = (args...) ->
		if req.canary
			args.unshift (Date.now() - req.time()) + 'ms'
			args.unshift req.tempID
			console.log.apply console.log, args
	next()

logTime = (name) -> (req, res, next) ->
	req.logTime name
	next()

server.use logTime 'start'

# parse the query string and JSON-body automatically
server.use restify.queryParser()
server.use logTime 'queryParser'

server.use (req, res, next) -> next null, req.headers['content-type'] = 'application/json'
server.use logTime 'force JSON'

server.use restify.bodyParser mapParams: false, requestBodyOnGet: true
server.use logTime 'bodyParser'

# use req.body in GET methods
server.use (req, res, next) ->
	if req.method is 'GET' and req.params.body
		req.body = JSON.parse req.params.body
		if typeof req.body is 'string'
			req.body = JSON.parse req.body
	next()
server.use logTime 'force body on GET'

server.use (req, res, next) ->
	res.notFound = (noun) -> @send 404, status: 'error', statusText: "There was no #{noun} found matching those parameters"

	req.params.asQuery = (allowed...) ->
		if allowed.length is 0
			allowed = (k for k, v of req.params)

		ret = {}
		for name in allowed when req.params[name]? and name isnt 'body'
			val = req.params[name]
			if typeof val isnt 'function'
				name = name.replace /[^a-z0-9_]+/ig, '_'
				ret[name] = val
		return ret

	next()
server.use logTime 'helpers'

# load models and routes automatically.
fs = require 'fs'
files = routes: {}, auth: {}
for dir of files
	for file in fs.readdirSync(__dirname + '/' + dir) when file.substr(-3) is '.js'
		name = file.slice 0, -3
		files[dir][name] = require __dirname + '/' + dir + '/' + file

global.Auth = files.auth
global.Routes = files.routes

for name, fn of Auth
	server.use Auth[name]

server.use logTime 'auth'

# parse date-likes in body
# this happens AFTER auth, to resolve any issues with hash matching
server.use (req, res, next) ->
	recurse = (obj) ->
		if obj and typeof obj is 'object'
			try
				keys = Object.keys obj
				for key in keys
					obj[key] = recurse obj[key]
		if typeof obj is 'string'
			if obj.match /^[0-9]{4}-(0?[0-9]|1[12])-[0-9]/
				date = Date.parse obj # regex:
				if not isNaN date
					obj = new Date date

		return obj

	recurse req.body
	next()
server.use logTime 'parse dates'

for group, fn of Routes
	fn server
server.use logTime 'routes'

# listen on the configured port.
console.log 'Listening on', config.api.port

server.listen config.api.port
