module.exports = (server) ->

	server.get '/conditions', Condition_Model.route, (req, res, next) ->
		req.model.loadPaginated {}, req, (err, response) ->
			if err then return req.throw err
			res.send response

	# Retrieve all conditions evaluated against this fact_type
	server.get '/conditions/:fact-type', Condition_Model.route, (req, res, next) ->
		req.model.loadPaginated {fact_type: req.params['fact-type']}, req, (err, response) ->
			if err then return req.throw err
			res.send response

	# Retrieve a specific condition, by ID
	server.get '/conditions/:fact-type/:condition-id', Condition_Model.route, (req, res, next) ->
		req.model.loadParams req.params, () ->
			res.send @export()

	# Update a specific condition, by ID
	server.post '/conditions/:fact-type/:condition-id', Condition_Model.route, (req, res, next) ->
		delete req.body._id
		req.body.fact_type = req.params['fact-type']
		req.body.condition_id = req.params['condition-id']

		req.model.update req.params, req.body, (err, updated) ->
			if err then return req.throw err
			res.send {
				status: 'ok',
				statusText: 'The condition was ' + (updated and 'updated.' or 'created.'),
				condition: @export()
			}

	# Delete a specific condition, by ID
	server.del '/conditions/:fact-type/:condition-id', Condition_Model.route, (req, res, next) ->
		req.model.loadParams req.params, (err, found) ->
			if found
				@remove () ->
					res.send {
						status: "ok",
						statusText: "The condition was removed."
					}
			else
				res.send 404, {
					status: "warning",
					statusText: "No such condition exists, so it was not removed."
				}

	# Test a condition against a specific fact.
	server.get '/conditions/:fact-type/:condition-id/test/:fact-id', (req, res, next) ->
		null
