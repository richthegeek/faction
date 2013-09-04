async = require 'async'
Model = require './model'
module.exports = class Fact_Model extends Model

	constructor: (@account, @type, callback) ->
		@type = type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60)

		super account.dbname(), @collectionname(type), (self, db, coll) ->
			callback.apply @, arguments

	_spawn: (callback) ->
		new @constructor @account, @type, callback

	collectionname: (type) ->
		'fact_' + type

	@route = (req, res, next) ->
		if req.params['fact-type']
			new Fact_Model req.account, req.params['fact-type'], () ->
				req.model = @
				next()
		else next()

	removeFull: (callback) ->
		@table.drop callback

	@getTypes = (account, callback) ->
		# open a connection to the database.
		mongodb.open account.dbname(), (err, db) ->
			# list all collections with the right name...
			db.collectionNames (err, collections) ->
				len = db.databaseName.length + 1
				result = (for coll in collections when 'fact_' is coll.name.substring len, len + 5
					coll.name.slice len + 5
				)

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
						if err then throw err
						obj = {}
						obj[fact.fact_type] = fact for fact in info
						callback obj

				callback result

	bindFunctions: (data = @export()) ->
		moment = require 'moment'

		JSON.parse JSON.stringify(data), (key, value) ->
			type = Object::toString.call(value).slice(8, -1)

			if type is 'Array'
				if (1 for item in value when item._value? and item._date?).length > 0
					value.over = (period, time) ->
						end = Number(time) or new Date().getTime()

						if bits = period.match(/^([0-9]+) (second|minute|hour|day|week|month|year)/)
							duration = moment.duration Number(bits[1]), bits[2]
							start = end - duration
							if 0 is duration.as 'milliseconds'
								throw 'Invocation of Array.over with invalid duration string.'

						else if seconds = Number(period)
							start = end - seconds

						else
							throw 'Invocation of Array.over with invalid duration value.'

						@betweenDates start, end

					value.before = (time) -> @betweenDates 0, time
					value.after = (time) -> @betweenDates time, new Date
					value.betweenDates = (start, end) -> @filter (item) -> start <= (new Date item._date or +new Date()) <= end


				value.values = () -> @filter((v) -> typeof v isnt 'function').map (v) -> v._value ? v
				value.sum = () -> @values().reduce ((pv, cv) -> pv + (cv | 0)), 0
				value.max = () -> @values().reduce ((pv, item) -> Math.max pv, item | 0), Math.max()
				value.min = () -> @reduce ((pv, item) -> Math.min pv, item | 0), Math.min()
				value.mean = () -> @sum() / @values().length

			return value
