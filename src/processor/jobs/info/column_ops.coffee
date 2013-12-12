getColumn = (row, column) ->
	result = []

	parts = column.split('.')
	left = parts.shift()
	column = parts.join('.')
	last = parts.length is 0

	# check for array operators: [0]
	index = false
	if m = left.match /(.+)\[(\*|-?[0-9]+)\]$/
		left = m[1]
		index = Number m[2]
		index = (if isNaN index then false else index)

	if row[left]?
		value = row[left]
		type = Object::toString.call(value).slice(8, -1).toString()

		if type == 'Array'
			value = (if index isnt false then value.slice(index).slice(0,1) else value)

			if last
				return value

			for e in value
				result = result.concat getColumn e, column

		else if type is 'Object'
			if last
				return [value]
			result = result.concat getColumn value, column

		else if last
			return [value]

		else
			console.log 'Failed get', arguments[1], row
			throw "Attempted to get child (#{column}) of an element which has no children (#{value}, is a #{type})."

	return result

setColumn = (row, column, new_value) ->
	# Assume no output expected if empty column
	if not column? or column is ""
		return row

	parts = column.split('.')
	left = parts.shift()
	column = parts.join('.')

	# check for array operators: [0]
	index = false
	if m = left.match /(.+)\[(\*|-?[0-9]+)\]$/
		left = m[1]
		index = Number m[2]
		index = (if isNaN index then false else index)

	# set value if at end
	if parts.length is 0
		if index isnt false
			row[left] ?= []
			if index < 0
				l = row[left].length or 0
				index = Math.max 0, l - index
			row[left][index] = new_value
		else
			row[left] = new_value
		return row

	# burrow if it already exists
	if row[left]?
		value = row[left]
		type = Object::toString.call(value).slice(8, -1).toString()

		if type == 'Array'
			value = (if index isnt false then value.slice(index, 1) else value)

			for i, e of value
				row[left][i] = setColumn e, column, new_value

		else if type is 'Object'
			row[left] = setColumn value, column, new_value

		else
			row[left] = new_value

	# create a new object/array if it doesnt
	else
		type = Object::toString.call(new_value).slice(8, -1).toString()

		if index is false or type is 'Object'
			row[left] = setColumn {}, column, new_value
		else
			row[left] = []
			row[left][index] = setColumn {}, column, new_value

	return row

deleteColumn = (row, column) ->
	if row._id?
		key = row._id.toString() + '.' + column

	try
		column = "['" + column.replace(/\./g, "']['") + "']"
		eval "delete row#{column}"
	catch e
		delete row[column]

	return row

module.exports = {
	getColumn: getColumn,
	setColumn: setColumn,
	deleteColumn: deleteColumn
}
