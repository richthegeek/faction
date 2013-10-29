module.exports =

	name: 'wait',
	description: 'Delay the next step.',
	fields: {
		delay: 'The number of seconds to delay until the next step'
	}

	validate: (info, callback) ->
		num = Number info.step.delay or -1
		if isNaN(num) or num <= 0
			return callback 'There must be a positive "delay" in number of seconds.'
		callback()

	exec: (info, next) ->

		# insert a new job for the delay.
		obj = JSON.parse JSON.stringify info.job
		obj.title += " (D#{info.stage})"
		obj.data.stage = info.stage

		jobs.create('perform_action', obj)
		  .delay(info.step.delay * 1000)
		  .save()

		return next {halt: true}
