async = require 'async'
Model = require './model'
module.exports = class Fact_Model extends Model

	constructor: (@account, @type, callback) ->
		@type = type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60)

		super account.dbname(), @collectionname(), (self, db, coll) ->
			callback.apply @, arguments

	_spawn: (callback) ->
		new @constructor @account, @type, callback

	@collectionname = @::collectionname = (type = @type) ->
		'facts_' + type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60)

	@route = (req, res, next) ->
		if req.params['fact-type']
			new Fact_Model req.account, req.params['fact-type'], () ->
				req.model = @
				next()
		else next()

	removeFull: (callback) ->
		@table.drop callback

	load: (query, shim, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		shim = args.pop() or false

		super query, callback
		# super query, () ->
		# 	@addShim callback

	loadAll: (query, shim, callback) ->
		args = Array::slice.call(arguments, 1)
		callback = args.pop()
		shim = args.pop() or false

		@table.find(query, {_id: 1}).toArray (err, ids) =>
			loader = (row, next) =>
				@_spawn () ->
					@load {_id: row._id}, shim, next

			async.map ids, loader, callback

	@getTypes = (account, callback) ->
		# open a connection to the database.
		mongodb.open account.dbname(), (err, db) ->
			# list all collections with the right name...
			db.collectionNames (err, cl) ->
				collections = cl

				rename = (row) -> return row.name.split('.').pop()
				filter = (name) -> return name.slice(0, 6) is 'facts_'
				trim   = (name) -> return name.slice(6)

				result = cl.map(rename).filter(filter).map(trim)

				result.detailed = (callback) ->
					iter = (type, next) ->
						new Fact_Model account, type, () ->
							@table.count (err, size) ->
								next err, {
									fact_type: type,
									fact_sources: 'todo',
									count: size,
									nextPage: "/facts/#{type}"
								}

					async.map result, iter, (err, info) ->
						obj = {}
						obj[fact.fact_type] = fact for fact in info or []
						callback err, obj

				callback err, result
