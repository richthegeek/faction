# add various functions to a fact:
#  - get(path): return values matching the given path
#  - Array functions:
#		- general: sum, max, min, mean, gt, gte, lt, lte, values
#		- temporal: over, before, after, betweendates, values

bindFunctions = require './bind_functions'

module.exports = (data, callback) ->
	bindFunctions data
	callback null, data
