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

	# Test a condition against a specific fact.
	server.get '/conditions/:fact-type/:condition-id/test/:fact-id', Condition_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery('fact-type', 'condition-id'), (err) ->
			condition = @
			new Fact_Model req.account, condition.data.fact_type, () ->
				@load {_id: req.params['fact-id']}, ErrorHandler next, (err) ->
					fact = @

					bound = fact.bindFunctions()

					catcher =
						log: () -> logged.push 'log', arguments
						error: () -> logged.push 'error', arguments
						info: () -> logged.push 'info', arguments
						warn: () -> logged.push 'warn', arguments

					code = """
					full = true;
					condition.resultBreakdown = condition.conditions.map(function(condition) {
						try {
							res = eval(condition);
							full = full && res;
							return res;
						} catch(e) {
							console.error(e);
							full = false;
							return false;
						}
					});
					condition.result = full;
					"""

					sandbox = {fact: bound, condition: condition.export(), console: console}
					require('contextify')(sandbox)
					sandbox.run code

					res.send {
						condition: condition,
						fact: fact,
						result: sandbox.condition.result
						result_breakdown: sandbox.condition.resultBreakdown
					}

					sandbox.dispose()
