traverse = require 'traverse'
url = require 'url'

module.exports = (data) ->
	traverse(data).forEach (value) ->
		if value and typeof value is 'string'
			obj = url.parse value
			if obj.pathname and obj.host
				for key, val of obj
					value[key] = val

				console.log 'Bind URL', value
				@update value, true

	return data
