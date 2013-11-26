traverse = require 'traverse'
url = require 'url'

module.exports = (data) ->
	traverse(data).forEach (value) ->
		if value and typeof value is 'string'

			obj = url.parse value, true
			if obj.pathname and obj.host

				if @parent.node.pathname? and @parent.node.host?
					return

				@update obj, true

	return data

module.exports.unbind = (data) ->
	traverse(data).forEach (value) ->
		if value.pathname and value.href
			@update value.href, true
