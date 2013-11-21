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


		console.log key, sub_path, old_val, new_val

		if key in ['$inc', '%inc']
			inc_by = Number(new_val) | 0
			old_val = old_val | 0
			n_f.set sub_path, old_val + inc_by

		else if key is '%addToSet'
			old_val = [].concat old_val
			# skip if already exists
			return for val in old_val when val is new_val
			# add to set else
			n_f.set sub_path, old_val.concat new_val

		else if key is '%push'
			old_val = [].concat old_val
			n_f.set sub_path, old_val.concat new_val


	# convert any dot notations into setColumn calls.
	for key, val of new_fact when key.indexOf('.') >= 0
		delete new_fact[key]
		setColumn new_fact, key, val

	return new_fact
