xtend = require 'xtend'
traverse = require 'traverse'
{getColumn, setColumn, deleteColumn} = require './column_ops'

module.exports = (settings, old_fact, mid_fact) ->
	old_fact ?= {}
	mid_fact ?= {}

	new_fact = xtend old_fact, mid_fact

	# apply the field_modes
	for field, mode of settings.field_modes when mid_fact[field]
		if mode.eval
			continue

		if mode is 'all'
			orig = old_fact[field] or []
			orig = [] if not Array.isArray orig
			list = orig.concat mid_fact[field]
			# ensure all entries are in the right format
			for k, v of list when not v._time
				list[k] =
					_time: (settings.time or new Date)
					_value: v

			setColumn new_fact, field, list.filter (v) -> !! v

		if mode is 'oldest'
			setColumn new_fact, field, old_fact[field] ? mid_fact[field]

		if mode is 'min'
			a = Number(mid_fact[field]) or Math.min()
			b = Number(old_fact[field]) or Math.min()
			setColumn new_fact, field, Math.min a, b

		if mode is 'max'
			a = Number(mid_fact[field]) or Math.max()
			b = Number(old_fact[field]) or Math.max()
			setColumn new_fact, field, Math.max a, b

	n_f = traverse(new_fact)
	o_f = traverse(old_fact)
	n_f.paths().filter((path) -> path[path.length - 1] is '$inc').forEach (path) ->
		sub_path = path.slice(0, -1)
		inc_by = n_f.get(path)
		old_val = o_f.get(sub_path) | 0
		n_f.set(sub_path, old_val + inc_by)

	return new_fact
