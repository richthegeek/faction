module.exports = (stream, config, row) ->
	return (fk, fact, next) ->
		# find in the collection using this query
		try
			config.models.infomapping.parseObject fk.query, {fact: fact}, (query) =>

				# execute any eval fields of the fact...
				modes = fact.getSettings().field_modes ? {}
				for key, props of modes when props.eval
					fact[key] = config.models.infomapping.eval props.eval, {fact: fact}

				# verify its not an empty query...
				size = 0
				for k, v of query when v?
					size++

				if size is 0
					return next()

				col = stream.db.collection config.models.fact.collectionname fk.fact_type
				col.find(query, {_id: 1}).toArray (err, ids) ->
					if err or ids.length is 0
						return next()

					next null, ids.map (id) ->
						id: id,
						type: fk.fact_type,
						time: +new Date

		catch e then do next
