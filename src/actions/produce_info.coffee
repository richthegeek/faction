module.exports =

	name: 'produce_info',
	description: 'Create new information to be mapped',

	validate: (info, callback) ->
		if not info.action.type
			return callback 'Must have a type'

		callback()

	exec: (info, next) ->
		info.fact.withMap [], info.action.map, (err, result) ->
			if err
				return next err

			new Info_Model info.fact.account, () ->
				@create info.action.type, result, (err) ->
					return next err, result
