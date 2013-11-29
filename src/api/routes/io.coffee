async = require 'async'
module.exports = (server) ->

	server.get '/export', Factsettings_Model.route, (req, res, next) ->
		db = req.model.db

		loadRows = (name, next) ->
			db.collection(name).find (err, cursor) -> cursor.toArray (err, res) -> next err, [name, res]

		async.map ['info_mappings', 'fact_settings', 'hooks'], loadRows, (err, results) ->
			output = {}
			for row in results
				output[row[0]] = row[1]

			res.header 'Content-Description', 'File Transfer'
			res.header 'Content-Type', 'text/json'
			res.header 'Content-Disposition', 'attachment; filename=faction-export.json'

			res.send JSON.stringify output


