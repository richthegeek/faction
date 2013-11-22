xtend = require 'xtend'
traverse = require 'traverse'
{getColumn, setColumn, deleteColumn} = require './column_ops'

module.exports = (settings, old_fact, mid_fact) ->
	old_fact ?= {}
	mid_fact ?= {}

	new_fact = xtend old_fact, mid_fact

	sets = {}

	settings.time ?= new Date

	# apply the field_modes
	for field, mode of settings.field_modes when value = mid_fact[field]
		if mode.eval
			continue

		old_value = old_fact[field]

		if mode is 'all'
			orig = old_value or []
			orig = [] if not Array.isArray orig
			list = orig.concat value
			# ensure all entries are in the right format
			for k, v of list when not v._time
				list[k] =
					_time: settings.time
					_value: v

			sets.$push ?= {}
			sets.$push[field] ?= {$each: []}
			sets.$push[field].$each.push {
				_time: settings.time
				_value: value
			}

			setColumn new_fact, field, list.filter (v) -> !! v

		if mode is 'oldest'
			if typeof old_value is 'undefined'
				sets.$set ?= {}
				sets.$set[field] = value

			setColumn new_fact, field, old_value ? value

		if mode in ['min', 'max']
			value = Math[mode].apply null, [value, old_value].map(Number).filter((x) -> ! isNaN x)

			sets.$set ?= {}
			sets.$set[field] = value

			setColumn new_fact, field, value

		if mode is 'inc'
			a = Number(value) or 1
			b = Number(old_value) or 0

			sets.$inc ?= {}
			sets.$inc[field] = a

			setColumn new_fact, field, a + b

		if mode is 'push'
			orig = old_value or []
			orig = [] if not Array.isArray orig
			list = orig.concat value


			sets.$push ?= {}
			sets.$push[field] ?= {$each: []}
			sets.$push[field].$each.push value

		if mode is 'push_unique'
			sets.$addToSet ?= {}
			sets.$addToSet[field] ?= {$each: []}
			sets.$addToSet[field].$each.push value


	# handle increment calls.
	n_f = traverse(new_fact)
	o_f = traverse(old_fact)
	n_f.paths().forEach (path) ->
		key = path[path.length - 1]

		if not key or key.charAt(0) not in ['$', '%']
			return

		sub_path = path.slice 0, -1
		new_val = n_f.get path
		new_val = new_val[key] or new_val
		old_val = o_f.get sub_path

		if key in ['$inc', '%inc']
			inc_by = Number(new_val) | 0
			old_val = old_val | 0
			n_f.set sub_path, old_val + inc_by


	# convert any dot notations into setColumn calls.
	for key, val of new_fact when key.indexOf('.') >= 0
		delete new_fact[key]
		setColumn new_fact, key, val

	return {fact: new_fact, updates: sets}
