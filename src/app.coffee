try require('source-map-support').install()

path = require 'path'
nconf = require 'nconf'
nconf.argv()
nconf.env()
nconf.file file: path.resolve(__dirname, '../config.json')
nconf.defaults {
	"mode": 'api'
}

global.config = nconf.get()

global.mongodb = require 'mongodb-opstream'

fs = require 'fs'
for file in fs.readdirSync(__dirname + '/models') when file.substr(-3) is '.js'
	name = file.slice(0, -3)
	name = name.slice(0,1).toUpperCase() + name.slice(1) + '_Model'
	global[name] = require __dirname + '/models/' + file

redis = require 'redis'
kue = require 'kue'
kue.redis.createClient = () -> redis.createClient config.redis.port, config.redis.host
global.jobs = kue.createQueue()

lynx = require 'lynx'
global.stats = new lynx config.statsd.host, config.statsd.port

if config.mode is 'api'
	require './api/index'

else if config.mode is 'kue-ui'
	if not config.kue?.port?
		console.error 'Kue-ui mode requires kue:port to be set'
		process.exit 0

	kue.app.listen config.kue.port
	kue.app.set 'title', 'Faction job queue'
	console.log 'Kue user interface listening on port', config.kue.port

else if config.mode is 'processor'
	require './processor/index'
