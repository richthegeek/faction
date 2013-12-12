module.exports = (server) ->

	server.get {path: '/', auth: false}, (req, res, next) ->
		res.suppressLog = req.suppressLog = true
		next res.send { status: 'ok', statusText: 'Faction, a data processing API that you\'re not cool enough to use' }

	server.get {path: '/ping', auth: false}, (req, res, next) ->
		res.suppressLog = req.suppressLog = true
		next res.send { status: 'ok', statusText: 'pong', time: +new Date }
