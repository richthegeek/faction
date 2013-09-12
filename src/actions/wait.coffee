module.exports =

	name: 'wait',
	description: 'Delay the next step.',
	fields: {
		delay: 'The number of seconds to delay until the next step'
	}

	validate: (action, callback) ->
		num = Number action.delay or -1
		if isNaN(num) or num <= 0
			return callback 'There must be a positive "delay" in number of seconds.'
		callback()

	exec: (info, next) ->
		http = require 'http'

		console.warn 'TODO: change hostname in wait action to api.faction.io'
		options =
			hostname: "localhost",
			port: 9876,
			path: "/actions/#{info.action.fact_type}/#{info.action.action_id}/exec/#{info.fact._id}/#{info.stage + 1}",
			method: 'GET'

		used_key = null
		text = 'GET ' + options.path
		for name, key of info.account.data.keys
			key.endpoints = [].concat key.endpoints
			if key.endpoints.length is 0 or (1 for regex in key.endpoints when new RegExp('^' + regex).test(text)).length > 0
				used_key = key
				break

		if not used_key
			return next 'The "wait" action requires at least one account key with access to GET /actions/.*/exec'

		hash_parts = []
		hash_parts.push options.path
		hash_parts.push JSON.stringify {}
		hash_parts.push used_key.private

		hash = require('crypto').createHash('sha256').update(hash_parts.join('')).digest('hex')

		options.path += '?key=' + used_key.public
		options.path += '&hash=' + hash

		http.get options, (res) ->
			res.setEncoding 'utf8'
			res.on 'data', (chunk) ->
				next null, 'Wait paused execution', true
				next = () -> null
