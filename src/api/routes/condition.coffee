module.exports = (server) ->

	server.get '/conditions', Condition_Model.route, (req, res, next) ->
		req.model.loadPaginated {}, req, ErrorHandler next, (err, response) ->
			res.send response

	# Retrieve all conditions evaluated against this fact_type
	server.get '/conditions/:fact-type', Condition_Model.route, (req, res, next) ->
		req.model.loadPaginated req.params.asQuery(), req, ErrorHandler next, (err, response) ->
			res.send response

	# Retrieve a specific condition, by ID
	server.get '/conditions/:fact-type/:condition-id', Condition_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery(), () ->
			res.send @export()

	# Update a specific condition, by ID
	server.post '/conditions/:fact-type/:condition-id', Condition_Model.route, (req, res, next) ->
		delete req.body._id
		req.body.fact_type = req.params['fact-type']
		req.body.condition_id = req.params['condition-id']

		req.model.update req.params.asQuery(), req.body, ErrorHandler next, (err, updated) ->
			res.send {
				status: 'ok',
				statusText: 'The condition was ' + (updated and 'updated.' or 'created.'),
				condition: @export()
			}

	# Delete a specific condition, by ID
	server.del '/conditions/:fact-type/:condition-id', Condition_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery(), ErrorHandler next, (err, found) ->
			if found
				@remove()
				res.send {
					status: "ok",
					statusText: "The condition was removed."
				}
			else
				res.send 404, {
					status: "warning",
					statusText: "No such condition exists, so it was not removed."
				}

	evaluate = (next, res, fact, condition) ->
		fact.addShim () =>
			fact.evaluateCondition condition, (err, results) =>
				next err or res.send {
					condition: condition.export(),
					fact: fact.export(),
					result: results.every(Boolean),
					result_breakdown: results
				}


	server.post '/conditions/:fact-type/:condition-id/test', Condition_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery('fact-type', 'condition-id'), (err) ->
			condition = @
			new Fact_deferred_Model req.account, condition.data.fact_type, () ->
				@import req.body, () ->
					evaluate next, res, @, condition


	# Test a condition against a specific fact.
	server.post '/conditions/:fact-type/:condition-id/test/:fact-id', Condition_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery('fact-type', 'condition-id'), (err) ->
			condition = @
			new Fact_deferred_Model req.account, condition.data.fact_type, () ->
				@load {_id: req.params['fact-id']}, ErrorHandler next, (err) ->
					evaluate next, res, @, condition
