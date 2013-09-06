module.exports = (server) ->

	# list all actions
	server.get '/actions', Action_Model.route, (req, res, next) ->
		req.model.loadPaginated {}, req, (err, response) ->
			if err then throw err
			res.send response

	# list all actions
	server.get '/actions/:fact-type', Action_Model.route, (req, res, next) ->
		req.model.loadPaginated req.params.asQuery(), req, (err, response) ->
			if err then throw err
			res.send response

	# get a specific action by ID
	server.get '/action/:fact-type/:action-id', Action_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery(), (err, found) ->
			if err then throw err
			if found
				res.send @export()
			else
				res.notFound 'action'

	# update a specific action by ID
	server.post '/action/:fact-type/:action-id', Action_Model.route, (req, res, next) ->
		req.body.action_id = req.params['action-id']
		req.body.fact_type = req.params['fact-type']
		req.model.update req.params.asQuery(), req.body, (err, updated) ->
			if err then return req.throw err
			res.send {
				status: 'ok',
				statusText: 'The action was ' + (updated and 'updated.' or 'created.'),
				action: @export()
			}

	# test an action against a fact, optionally forcing a bypass of conditions.
	server.get '/action/:fact-type/:action-id/test/:fact-id', Action_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery('fact-type', 'action-id'), (err, found) ->
			if err then throw err
			if not found then return res.notFound 'action'

			action = @
			new Fact_Model req.account, action.data.fact_type, (err) ->
				@load {_id: req.params['fact-id']}, (err, found) ->
					if err then throw err
					if not found then return res.notFound 'fact'

					fact = @
					if req.query.force or action.fact_is_runnable fact
						action.fact_run fact, (err, results) ->
							res.send {
								status: 'ok',
								statusText: 'The action was run using this fact.',
								action: action,
								fact: fact,
								result: results,
								forced: req.query.force
							}
					else
						res.send {
							status: 'ok',
							statusText: 'The action was not run because the fact did not pass the conditions.',
							action: action,
							fact: fact,
							result: false
						}

	server.del '/action/:fact-type/:action-id', Action_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery(), (err, found) ->
			if found
				@remove () ->
					res.send {
						status: "ok",
						statusText: "The action was removed."
					}
			else
				res.send 404, {
					status: "warning",
					statusText: "No such action exists, so it was not removed."
				}
