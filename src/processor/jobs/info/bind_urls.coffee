traverse = require 'traverse'
url = require 'url'

module.exports = () ->

	if not ("http://www.google.com".host?)
		Object.keys(url.parse('')).forEach (key) ->
			Object.defineProperty String::, key, get: ->
				value = url.parse(this.toString(), true)[key]
				console.log '  url', key, value
				return value
