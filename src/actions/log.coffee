module.exports =

	name: 'log',
	description: 'Simply log some information',

	validate: (action, callback) ->
		return callback 'I cant do that dave'
		callback null, true

	exec: (info, next) ->
		return next null, info.step.message
