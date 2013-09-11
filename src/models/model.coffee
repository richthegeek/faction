check = require('validator').check

module.exports = class Model

	constructor: (db, collection, callback) ->
		mongodb.open db, collection, (err, @db, @table) =>
			if callback
				callback.call @, @, db, table

	_spawn: (callback) ->
		new @constructor @db, @table, callback

	setup: () -> null

	import: (data, callback) ->
		@data = @data or {}
		for k,v of data or {}
			@data[k] = v
		callback.call @, @data

	export: () -> @data
	@export = (data) -> @::export.call({data: data})

	toJSON: () -> @export()

	load: (conditions, callback) ->
		if (conditions instanceof mongodb.ObjectID) or (typeof conditions in ['string', 'number'])
			conditions = {_id: conditions}

		@table.findOne conditions, (err, row) =>
			@import row, () =>
				callback.call @, err, @, conditions

	paramsToQuery: (params) ->
		query = {}
		for name, value of params
			name = name.replace /-/g, '_'
			query[name] = value
		return query

	loadParams: (params, callback) ->
		@load params.asQuery(), callback

	loadPaginated: (conditions, req, callback) ->
		# get numerical params from the req.
		req.query.page ?= 0
		req.query.limit ?= 100

		check(req.query.page, {
			isInt: 'The page query parameter must be numeric',
			min: 'The page query parameter must be greater than zero.'
		}).isInt().min(0)

		check(req.query.limit, {
			isInt: 'The limit query parameter must be numeric',
			min: 'The limit query parameter must be greater than one.'
		}).isInt().min(1)

		skip = req.query.page * req.query.limit

		@table.find conditions, (err, cursor) =>
			if err then return callback err
			cursor.count (err, size) =>
				cursor.skip(skip).limit(req.query.limit).toArray (err, items) =>

					new Grouped_Model @, items, () ->

						response =
							page: req.query.page,
							limit: req.query.limit,
							totalItems: size,
							totalPages: Math.ceil(size / req.query.limit),
							nextPage: null,
							prevPage: null
							items: @

						if req.query.page + 1 < response.totalPages
							response.nextPage = req.path + "?page=#{req.query.page + 1}&limit=#{req.query.limit}"

						if req.query.page > 0
							response.prevPage = req.path + "?page=#{req.query.page - 1}&limit=#{req.query.limit}"

						callback.call @, err, response

	validate: (data, callback) ->
		callback()

	save: (callback) ->
		try
			@validate @export(), (err) =>
				if err then throw err

				@table.save @data, (err) =>
					if err then throw err
					callback.apply @, arguments

		catch e
			return callback e


	remove: (conditions, callback) ->
		if typeof conditions is 'function'
			callback = conditions
			conditions = {}
			conditions._id = @export()._id

			if not conditions._id
				throw 'Model does not have an ID, so remove was not called.'

		@table.remove conditions, (err) =>
			if err then throw err
			callback.apply @, arguments

	update: (query, data, callback) ->
		@load query, (err, updated, query) =>
			@import data, () =>
				if updated
					@before_update()
				else
					@before_create()

				@save (err) =>
					console.log 5
					callback.call @, err, updated

	before_update: () -> null
	before_create: () -> null
