module.exports = class Model

	constructor: (db, collection, callback) ->
		mongodb.open db, collection, config.mongo.host, config.mongo.port, (err, @db, @table) =>
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
				callback.call @, err, row, conditions

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
		req.query.page = Number req.query.page ? 0
		req.query.limit = Number req.query.limit ? 100

		if isNaN(req.query.page) or req.query.page < 0
			return callback 'The page query parameter must be numeric and greater than 0'

		if isNaN(req.query.limit) or req.query.limit < 1
			return callback 'The limit query parameter must be numeric and greater than 1'

		skip = req.query.page * req.query.limit

		@table.find conditions, (err, cursor) =>
			if err then return callback err
			cursor.count (err, size) =>
				sort = false
				if req.params.sort
					bits = req.params.sort.toString().split(',')
					sort = {}
					for param in bits
						if param.substring(0, 1) is '-'
							sort[param.slice(1)] = -1
						else
							sort[param] = 1
				if req.body.sort
					sort = {}
					for key, val of req.body.sort
						sort[key] = (val is 'desc' and -1) or 1

				if sort isnt false
					cursor.sort(sort)

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

	create: (data, callback) ->
		@import data, () =>
			@save callback

	save: (callback) ->
			@validate @export(), (err) =>
				if err then return callback err
				@table.save @data, () => callback.apply @, arguments

	remove: (conditions, callback) ->
		if typeof conditions is 'function'
			callback = conditions
			conditions = {}
			conditions._id = @data._id

			if not conditions._id
				return callback 'Model does not have an ID, so remove was not called.'

		@table.remove conditions, () => callback.apply @, arguments

	update: (query, data, updateOnly, callback) ->
		if typeof updateOnly is 'function'
			callback = updateOnly
			updateOnly = false

		@load query, (err, updated, query) =>
			if updateOnly and not updated
				return callback 'Not Found'

			@import data, () =>
				if updated
					@before_update()
				else
					@before_create()

				@save (err) =>
					callback.call @, err, updated

	before_update: () -> null
	before_create: () -> null
