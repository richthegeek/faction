crypto = require 'crypto'
Model = require './model'
Cache = require 'shared-cache'

module.exports = class InfoMapping_Model extends Model

	constructor: (@account, callback) ->
		super account.dbname(), 'info_mappings', callback

	_spawn: (callback) ->
		new @constructor @account, callback

	@route = (req, res, next) ->
		new InfoMapping_Model req.account, () ->
			req.model = @
			next()

	setup: () ->
		@table.ensureIndex {mapping_id: 1, info_type: 1}, {unique: true}, () -> null
		@table.ensureIndex {fact_type: 1}, {}, () -> null

	validate: (data, callback) ->
		if not data.fact_type
			return callback 'An information-mapping should have a fact_type property.'

		if not data.fact_query
			return callback 'An information-mapping should have a fact_query property defining how a fact is loaded.'

		if not data.fields or typeof data.fields isnt 'object'
			return callback 'An information-mapping should have a fields property defining how data is mapped to facts.'

		if not data.mapping_id
			return callback 'An information-mapping must have an ID defined. (This error should not be seen).'

		callback()

	save: () ->
		# mark the mapping cache as stale
		Cache.create('info-mappings-' + @account.data._id, false, (key, next) => @table.find().toArray next).stale()
		super

	export: () ->
		return {
			mapping_id: @data.mapping_id,
			fact_type: @data.fact_type,
			fact_query: @data.fact_query,
			fields: @data.fields
		}


	setup: ->
		@db.addStreamOperation {
			_id: 'info_handlers',
			type: 'untracked',
			operations: [{operation: 'info_mapping'}],

			sourceCollection: 'info',
			targetCollection: 'fact_updates'
		}

		@db.addStreamOperationType 'info_mapping', {
			dependencies: {
				cache: 'shared-cache',
				async: 'async',
				xtend: 'xtend',
				'account': __dirname + '/account',
				'fact': __dirname + '/fact'
			},

			eval: (str, context) ->
				try
					`with(context) { result = eval(str) }`
					return result
				catch e
					return str

			###
			interpolate: evaluate demarcated sections of a string
			###
			interpolate: (str, context) ->
				sections = str.match /\#\{.+?\}/g
				for section in sections or []
					str = str.replace section, @eval section.slice(2, -1), context
				return str

			###
			parseObject: evaluate the object with this context, interpolating keys and evaluating leaves.
				Should transform an object like:
					"orders": "item", "order_#{item.oid}_value": "item.value"
				Into this:
					"orders": {oid: 42, value: 400}, "orders_42_value": 400
			###
			parseObject: (obj, context) ->
				JSON.parse (JSON.stringify obj), (key, value) =>
					# interpolate keys
					if Object::toString.call(value) is '[object Object]'
						for k, v of value
							delete value[k]
							k = @interpolate k, context
							value[k] = v

					# evaluate strings
					if typeof value is 'string'
						value = @eval value, context

					return value

			exec: (row, callback) ->
				_mappings = @modules.cache.create 'info-mappings-' + @account, true, (key, next) =>
					@stream.db.collection('info_mappings').find().toArray next
				_settings = @modules.cache.create 'fact-settings-' + @account, true, (key, next) =>
					@stream.db.collection('fact_settings').find().toArray next


				###
				A sample mapping:
					info_type: 'visit',
					fact_type: 'user',
					fact_query: '{session_id: info.session_id}',
					fields:
						session_id: 'info.session_id'
						visits:
							url: 'info.url',
							time: 'new Date'
				With this we need to:
				 - run the fact_query against the facts_user collection
				 - create the object mapping
				 - load the fact settings for the "user" fact (cache!)
				 - execute the fact settings and save.

				A sample fact setting:
					fact_type: 'user'
					field_modes:
						session_id: 'all'
						visits: 'all'
					primary_key: ['customer_id']

				With this we need to:
				 - apply the mapping to the fact
				 - check that the primary key doesnt result in multiple db entries. If so, merge
				 - save the damn fact
				###

				self = @
				time = row._id.getTimestamp()

				return _mappings.get (err, mappings) ->
					_settings.get (err, settings) ->
						iterator = (mapping, next) ->
							if mapping.info_type isnt row._type
								return next()

							query = self.parseObject mapping.fact_query, {info: row}

							facts_col = self.stream.db.collection self.modules.fact.collectionname row._type
							facts_col.find(query).toArray (err, facts) ->
								if err
									return next err

								# ensure there is at least one fact
								if facts.length is 0
									facts.push {}

								delete row._type
								delete row._id if Object::toString.call(row._id) is '[object Object]'

								# evaluate the mapping against each fact
								next null, facts.map (fact) ->
									obj = self.parseObject mapping.fields, {info: row, fact: fact}
									# copy over the query fields, if they aren't otherwise set
									obj[k] ?= v for k, v of query

									return {
										collection: facts_col,
										fact: fact,
										mapping: mapping,
										info: obj
									}

						self.modules.async.map mappings, iterator, (err, result) ->
							# flatten results into single array
							result = [].concat.apply([], result).filter (r) -> !! r

							iterator = (info, next) ->
								setting = (set for set in settings when set._id is info.mapping.fact_type).pop()
								setting ?= {field_modes: {}, primary_key: ['_id']}

								mergeFacts = (old_fact, mid_fact) ->
									new_fact = self.modules.xtend old_fact, mid_fact

									# apply the field_modes
									for field, mode of setting.field_modes when mid_fact[field]
										if mode is 'all'
											orig = old_fact[field] or []
											orig = [] if not Array.isArray orig
											list = orig.concat mid_fact[field]
											# ensure all entries are in the right format
											for k, v of list when not v._time
												list[k] =
													_time: new Date
													_value: v

											for i in [0...list.length] when a = list[i]
												ac = JSON.stringify(a._value)
												for j in [(i+1)...list.length] when b = list[j]
													if (a._time - b._time is 0) and ac is JSON.stringify(b._value)
														# these two are the same.
														console.log 'EQ', i, j
														list[j] = false

											new_fact[field] = list.filter (v) -> !! v

										if mode is 'oldest'
											new_fact[field] = old_fact[field] or mid_fact[field]

										if mode is 'min'
											a = Number(mid_fact[field]) or Math.min()
											b = Number(old_fact[field]) or Math.min()
											new_fact[field] = Math.min a, b

										if mode is 'max'
											a = Number(mid_fact[field]) or Math.max()
											b = Number(old_fact[field]) or Math.max()
											new_fact[field] = Math.max a, b

									return new_fact

								result = mergeFacts info.fact, info.info
								query = {}
								id = []
								for field in setting.primary_key
									id.push query[field] = result[field]

								# load + merge using the PK
								info.collection.findOne query, (err, existing) ->
									if err then return next err

									existing ?= {}
									fact = result

									if existing._id and (existing._id isnt info.fact._id)
										fact = mergeFacts existing, result

									fact._id = id.join('-')

									info.collection.update {_id: fact._id}, fact, {upsert: true}, (err) ->
										console.log 4, arguments
										# write to fact_updates
										next err, {
											id: fact._id,
											type: info.mapping.fact_type,
											time: +new Date
										}

							self.modules.async.map result, iterator, () ->
								console.log 'COMPLETE', arguments

								# callback
		}
