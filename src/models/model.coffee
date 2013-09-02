check = require('validator').check
module.exports = class Model

	constructor: (db, collection, callback) ->
		mongodb.open db, collection, (err, db, table) =>
			@db = db
			@table = table
			if callback
				callback.call @, @, db, table


	export: () ->
		return @data

	load: (conditions, callback) ->
		if (conditions instanceof mongodb.ObjectID) or (typeof conditions in ['string', 'number'])
			conditions = {_id: conditions}

		@table.findOne conditions, (err, row) =>
			if row
				@data = row
			callback.call @, err, row

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

		@table.find conditions, (err, cursor) ->
			if err then return callback err
			cursor.count (err, size) ->
				cursor.skip(skip).limit(req.query.limit).toArray (err, items) ->
					response =
						page: req.query.page,
						limit: req.query.limit,
						totalItems: size,
						totalPages: Math.ceil(size / req.query.limit),
						nextPage: null,
						prevPage: null
						items: items

					if req.query.page + 1 < response.totalPages
						response.nextPage = req.path + "?page=#{req.query.page + 1}&limit=#{req.query.limit}"

					if req.query.page > 0
						response.prevPage = req.path + "?page=#{req.query.page - 1}&limit=#{req.query.limit}"

					callback err, response


	save: (callback) ->
		@table.save @data, callback

	remove: (conditions, callback) ->
		if typeof conditions is 'function'
			callback = conditions
			conditions = {}
			conditions._id = @export()._id

			if not data._id
				callback 'Model does not have an ID, so remove was not called.'

		@table.remove conditions, callback
