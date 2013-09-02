mongodb = require 'mongodb-opstream'

global.config = config or {}
config.db ?= {}
config.db?.host ?= 'localhost'
config.db?.port ?= 27017

mongodb.open = (name, collection, callback) ->
	if typeof collection is 'function'
		callback = collection
		collection = null

	if cached = mongodb.open_cache name, collection
		return callback null, cached.database, cached.collection

	options =
		'native_parser': false
		'w': 1
		'wtimeout': 100

	server = new mongodb.Server config.db.host, config.db.port
	db = mongodb.Db name, server, options
	db.open (err, db) ->
		if not collection
			mongodb.open_cache name, null, db
			callback null, db, null
		else
			db.collection collection, ( err, col ) ->
				mongodb.open_cache name, collection, col
				callback null, db, col

mongodb.open_cache = (name, collection, set) ->
	@cache ?= {}

	if set
		@cache[name] ?= {db: set, collections: {}}
		@cache[name].db = set
		if collection
			@cache[name].db = set.db
			@cache[name].collections[collection] = set

	else if cache = @cache[name]
		collection = cache.collections[collection]
		return {database: cache.db, collection: collection}

module.exports = mongodb
