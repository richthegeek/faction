module.exports = wrapArray = (arr) ->
	return arr unless Array.isArray arr

	# get distinct keys of objects
	keys = {}
	for row in arr when Object::toString.call(row) is '[object Object]'
		for k in Object.keys(row)
			keys[k] = true

	Object.keys(keys).forEach (key) ->
		Object.defineProperty arr, key, get: =>
			result = wrapArray [].concat.apply [], arr.map((row) -> row[key]).filter(Boolean)
			return result

	return arr
