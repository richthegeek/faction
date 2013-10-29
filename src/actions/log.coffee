module.exports =

	name: 'log',
	description: 'Simply log some information',

	validate: (action, callback) ->
		callback()

	exec: (info, next) ->
		console.log info.step.log
		return next null, info.step.log
