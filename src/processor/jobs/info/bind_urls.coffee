traverse = require 'traverse'
url = require 'url'

module.exports = (data) ->
	traverse(data).forEach (value) ->
		if value and typeof value is 'string'
			obj = url.parse value
			if obj.pathname and obj.host
				obj.toString = -> @href
				obj.toJSON = -> @toString()
				@update obj, true

	return data
