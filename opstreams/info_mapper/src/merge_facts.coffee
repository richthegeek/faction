module.exports = (stream, config, row) ->
	xtend = require 'xtend'

	{getColumn, setColumn, deleteColumn} = require('./column_ops')()

	return (settings, old_fact, mid_fact) ->
		new_fact = xtend old_fact, mid_fact

		# apply the field_modes
		for field, mode of settings.field_modes when mid_fact[field]
			if mode is 'all'
				orig = old_fact[field] or []
				orig = [] if not Array.isArray orig
				list = orig.concat mid_fact[field]
				# ensure all entries are in the right format
				for k, v of list when not v._time
					list[k] =
						_time: config.time
						_value: v

				# de-dup in case of double-processed event (shouldnt happen but...)
				for i in [0...list.length] when a = list[i]
					ac = JSON.stringify(a._value)
					for j in [(i+1)...list.length] when b = list[j]
						if (a._time - b._time is 0) and ac is JSON.stringify(b._value)
							# these two are the same.
							list[j] = false


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

		return new_fact
