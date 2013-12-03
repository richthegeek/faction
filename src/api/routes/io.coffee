async = require 'async'
module.exports = (server) ->

	server.get '/export', Factsettings_Model.route, (req, res, next) ->
		db = req.model.db

		cols = ['info_mappings', 'fact_settings', 'hooks'].filter (v) -> req.body[v] isnt false

		async.map cols
			,(name, next) ->
				db.collection(name).find (err, cursor) -> cursor.toArray (err, res) -> next err, [name, res]
			,(err, results) ->
				output = {}
				for row in results
					output[row[0]] = row[1].map (el) ->
						if row[0] isnt 'fact_settings'
							delete el._id
						return el

				output = JSON.stringify output

				res.header 'Content-Description', 'File Transfer'
				res.header 'Content-Type', 'application/javascript'
				res.header 'Content-Disposition', 'attachment; filename=faction-export.json'
				res.header 'Content-Length', output.length

				res.write output
				res.end()

				next()

	server.post '/import', Factsettings_Model.route, (req, res, next) ->
		db = req.model.db

		data = []

		if req.body.fact_settings
			data.push ['fact_settings', req.body.fact_settings]

		if req.body.info_mappings
			data.push ['info_mappings', req.body.info_mappings]
			for entry in req.body.info_mappings
				if not entry.mapping_id then return next new restify.InvalidArgumentError 'Info mappings must have a mapping_id'
				if not entry.fact_type then return next new restify.InvalidArgumentError 'Info mappings must have a fact_type'
				if not entry.fact_identifier then return next new restify.InvalidArgumentError 'Info mappings must have a fact_identifier'
				if not entry.info_type then return next new restify.InvalidArgumentError 'Info mappings must have a info_type'

		if req.body.hooks
			data.push ['hooks', req.body.hooks]
			for entry in req.body.hooks
				if not entry.hook_id then return next new restify.InvalidArgumentError 'Hooks must have a hook_id'
				if not entry.fact_type then return next new restify.InvalidArgumentError 'Hooks must have a fact_type'
				if not entry.type then return next new restify.InvalidArgumentError 'Hooks must have a type'

		async.map data
			, (row, next) ->
				[name, entries] = row

				collection = db.collection(name)
				# empty stuff...
				collection.remove (err) ->
					if err then return next err

					async.map entries, collection.insert.bind(collection), next

			, (err, result) ->
				next res.send arguments
