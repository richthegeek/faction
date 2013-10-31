{getColumn, setColumn, deleteColumn} = require './column_ops'
module.exports = (data) ->
	moment = require 'moment'
	traverse = require 'traverse'

	bind_array = (value) ->
		if (1 for item in value when item._value? and item._date?).length > 0
			value.over = (period, time) ->
				end = Number(time) or new Date().getTime()

				if bits = period.match(/^([0-9]+) (second|minute|hour|day|week|month|year)/)
					duration = moment.duration Number(bits[1]), bits[2]
					start = end - duration
					if 0 is duration.as 'milliseconds'
						throw 'Invocation of Array.over with invalid duration string.'

				else if seconds = Number(period)
					start = end - seconds

				else
					throw 'Invocation of Array.over with invalid duration value.'

				@betweenDates start, end

			value.before = (time) -> @betweenDates 0, time
			value.after = (time) -> @betweenDates time, new Date
			value.betweenDates = (start, end) -> bind_array @filter (item) -> new Date(start) <= (new Date item._date or new Date()) <= new Date(end)


		value.values = (column) ->
			return bind_array @filter((v) -> typeof v isnt 'function').map (v) ->
				v = v._value ? v
				return (column and v[column] or v)

		value.sum  = (column) -> @values(column).reduce ((pv, cv) -> pv + (cv | 0)), 0
		value.max  = (column) -> @values(column).reduce ((pv, item) -> Math.max pv, item | 0), Math.max()
		value.min  = (column) -> @values(column).reduce ((pv, item) -> Math.min pv, item | 0), Math.min()
		value.mean = (column) -> @sum(column) / @values(column).length

		compare = (column, val, fn) ->
			args = Array::slice.call arguments
			fn = args.pop()
			val = args.pop()
			column = args.pop()
			@values(column).filter (v) -> fn val, v
		value.gt  = (column, val) -> compare.call @, column, val, (val, v) -> v > val
		value.gte = (column, val) -> compare.call @, column, val, (val, v) -> v >= val
		value.lt  = (column, val) -> compare.call @, column, val, (val, v) -> v < val
		value.lte = (column, val) -> compare.call @, column, val, (val, v) -> v <= val

		value.match = (params) ->
			# allow calling like (key, val, key, val, key, val)
			args = Array::slice.call arguments
			if args.length > 1 and typeof args[0] is 'string'
				params = {}
				while args.length >= 2
					params[args.shift()] = args.shift()

			v = @values().filter (row) ->
				for own key, val of params
					test = (row_val) -> val is row_val
					if not val
						test = (row_val) -> not row_val

					# if it's a regex-like string (/....../) try parse it.
					if typeof val is 'string' and r = val.match /^\/(.+)\/$/
						try
							reg = new RegExp r[1]
							test = (row_val) -> reg.test(val)
						catch e
							return false

					if not test row[key]
						return false

				return true
			return v

		return value

	bind_iterable = (value) ->
		value.get = (args...) ->
			args = args.join '.'
			r = getColumn @, args
			if Array.isArray r
				r = bind_array r
			return r

		value.set = (col, val) ->
			return setColumn @, col, val

		value.del = (col) ->
			return deleteColumn @, col

	if data
		bind_iterable data

	traverse(data).forEach (value) ->
		type = Object::toString.call(value).slice(8, -1)

		if type is 'Array'
			value = bind_array value

		if type in ['Object', 'Array']
			value = bind_iterable value

		@update value

	return data
