check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class Info_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	create: (type, info, callback) ->
		if typeof info is 'function'
			callback = info
			info = {}

		delete info._id
		info._type = type
		@table.insert info, callback

	@route = (req, res, next) ->
		new Info_Model req.account, () ->
			req.model = @
			next()

	setup: ->
		@table.addStreamOperation {
			_id: 'info_handlers',
			type: 'untracked',
			operations: [{operation: 'info_multiplex'}],
			targetCollection: 'fact_updates'
		}

		@table.addStreamOperationType 'info_multiplex', {
			dependencies: {
				cache: 'shared-cache',
				async: 'async'
			},
			exec: (row, callback) ->
				handler_cache = @modules.cache.create 'info-handlers-' + @account, true, (key, next) =>
					@stream.db.collection('info_handlers').find().toArray(next)

				interpolate = (str, fact, info) ->
					context = {
						fact: fact,
						info: info
					}
					sections = str.match /\#\{.+?\}/g
					for section in sections
						`with(context) { result = eval(section.slice(2,-1)) }`
						str = str.replace section, result

					return str

				time = row._id.getTimestamp()
				modes =
					all: (fact, set, col, val) ->
						set.$push ?= {}
						set.$push[col] = {_value: val, _date: time}

					oldest: (fact, set, col, val) ->
						if not fact[col]?
							set.$set ?= {}
							set.$set[col] = val

					newest: (fact, set, col, val) ->
						set.$set ?= {}
						set.$set[col] = val

					min: (fact, set, col, val) ->
						min = fact[col] ? Math.min()
						if Number(val) < min
							set.$set ?= {}
							set.$set[col] = val

					max: (fact, set, col, val) ->
						max = fact[col] ? Math.max()
						if Number(val) > max
							set.$set ?= {}
							set.$set[col] = val

				handler_cache.get (err, handlers, cache_hit) =>
					iterator = (handler, next) =>
						if handler.info_type isnt row._type
							return next()

						# each handler needs to:
						#  - try find an existing fact using the identifier
						#  - get any track data
						#  - use atomic updates to add this data to the fact
						try
							id = interpolate handler.fact_identifier, fact, row

							type = handler.fact_type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60)
							collection = @stream.db.collection('fact_' + type)
							collection.findOne {_id: id}, (err, fact) =>
								set = {}
								fact = fact or {}
								for mode, columns of handler.track
									for col, str of columns
										val = interpolate str, fact, row

										if fn = modes[mode]
											fn fact, set, col, val

								collection.update {_id: id}, set, {upsert: true}, (err) ->
									# write to fact_updates
									next err, {
										id: id,
										type: type,
										time: +new Date,
										query: JSON.stringify set
									}

						catch e
							update =
								$push:
									errors:
										$each: [{message: e.toString(), time: new Date}]
										$slice: -10
							@stream.db.collection('info_handlers').update {_id: handler._id}, update
							console.error 'Info_Handler failure', e
							next()

					@modules.async.map handlers, iterator, (err, rows) ->
						callback err, rows
		}
