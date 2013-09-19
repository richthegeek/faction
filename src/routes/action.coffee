module.exports = (server) ->

	# list all action-types
	server.get '/action-types', Action_Model.route, (req, res, next) ->
		req.model.actionTypes ErrorHandler next, (err, types) ->
			res.send types

	# list all actions
	server.get '/actions', Action_Model.route, (req, res, next) ->
		req.model.loadPaginated {}, req, ErrorHandler next, (err, response) ->
			res.send response

	# list all actions
	server.get '/actions/:fact-type', Action_Model.route, (req, res, next) ->
		req.model.loadPaginated req.params.asQuery(), req, ErrorHandler next, (err, response) ->
			res.send response

	# get a specific action by ID
	server.get '/actions/:fact-type/:action-id', Action_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery(), ErrorHandler next, (err, found) ->
			if found
				res.send @export()
			else
				res.notFound 'action'

	# update a specific action by ID
	server.post '/actions/:fact-type/:action-id', Action_Model.route, (req, res, next) ->
		req.body.action_id = req.params['action-id']
		req.body.fact_type = req.params['fact-type']
		req.model.update req.params.asQuery(), req.body, ErrorHandler next, (err, updated) ->
			res.send {
				status: 'ok',
				statusText: 'The action was ' + (updated and 'updated.' or 'created.'),
				action: @export()
			}

	# test an action against a fact, optionally forcing a bypass of conditions.
	server.get '/actions/:fact-type/:action-id/test/:fact-id', Action_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery('fact-type', 'action-id'), (err, found) ->
			if err or not found
				return next err or res.notFound 'action'

			action = @
			new Fact_Model req.account, action.data.fact_type, (err) ->
				@load {_id: req.params['fact-id']}, ErrorHandler next, (err, found) ->
					if err or not found
						return next err or res.notFound 'fact'

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

	action_exec = (req, res, next) ->
		req.params.stage ?= 0
		req.model.load req.params.asQuery('fact-type', 'action-id'), (err, found) ->
			if err or not found
				return next err or res.notFound 'action'
			action = @
			new Fact_Model req.account, action.data.fact_type, (err) ->
				@load {_id: req.params['fact-id']}, ErrorHandler next, (err, found) ->
					if err or not found
						return next err or res.notFound 'fact'
					fact = @
					@db.collection('fact_evaluated').insert {
						id: fact.data._id,
						type: fact.type,
						result: {},
						time: +new Date,
						stage: req.params.stage
					}
					res.send {
						status: 'ok',
						statusText: 'The action was queued to be executed',
						action: action,
						fact: fact
					}

	server.get '/actions/:fact-type/:action-id/exec/:fact-id', Action_Model.route, action_exec
	server.get '/actions/:fact-type/:action-id/exec/:fact-id/:stage', Action_Model.route, action_exec

	server.del '/actions/:fact-type/:action-id', Action_Model.route, (req, res, next) ->
		req.model.load req.params.asQuery(), ErrorHandler next, (err, found) ->
			if found
				@remove()
				res.send {
					status: "ok",
					statusText: "The action was removed."
				}
			else
				res.send 404, {
					status: "warning",
					statusText: "No such action exists, so it was not removed."
				}

	# list history of an action against a fact
	server.get '/actions/:fact-type/:action-id/history/:fact-id', Actionresult_Model.route, (req, res, next) ->
		req.model.loadPaginated req.params.asQuery(), req, ErrorHandler next, (err, response) ->
			res.send response
