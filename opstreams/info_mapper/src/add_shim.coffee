module.exports = (stream, config, row) ->

	bindFunctions = require('./bind_functions')(stream, config, row)

	# add various functions to a fact:
	#  - get(path): return values matching the given path
	#  - Array functions:
	#		- general: sum, max, min, mean, gt, gte, lt, lte, values
	#		- temporal: over, before, after, betweendates, values

	return (data, callback) ->
		bindFunctions data
		callback null, data

	return addShim
