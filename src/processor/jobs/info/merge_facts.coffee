moment = require 'moment'
xtend = require 'xtend'
{getColumn, setColumn, deleteColumn} = require './column_ops'

module.exports = (settings, old_fact, mid_fact) ->
	settings.time ?= new Date
	old_fact ?= {}
	mid_fact ?= {}

	sets = {}

	for key, val of mid_fact
		if old_fact?[key]? and old_fact[key] is mid_fact[key]
			continue
		sets[key] = {type: '$set', value: val}

	new_fact = xtend old_fact, mid_fact

	# apply the field_modes
	for field, val of settings.field_modes
		# mode can be a string or an object with a mode property
		mode = val.mode or val

		if mode is 'eval' or val.eval
			delete sets[field]
			continue

		value = getColumn(mid_fact, field).shift()

		formats =
			day: 'YYYY-MM-DD'
			week: 'YYYY-WW'
			month: 'YYYY-MM'
			year: 'YYYY'
		if format = formats[val.grouping]
			if mode in ['newest', 'oldest', 'inc', 'min', 'max']
				delete sets[field]
				field = field + '.' + moment().format format

		old_value = getColumn(old_fact, field).shift()

		# allow not-null for inc
		if mode is 'inc' and (mid_fact[field]? or val.not_null isnt true)
			a = Number(value) or 1
			b = Number(old_value) or 0
			sets[field] = {type: '$inc', value: a}

		# following field modes require a value to be set
		if not value
			continue

		switch mode
			when 'inc_map'
				value = value.replace /\./g, '%2E'
				sets[field + '.' + value] = {type: '$inc', value: 1}

			when 'all'
				orig = old_value or []
				orig = [] if not Array.isArray orig
				list = orig.concat value
				# ensure all entries are in the right format
				for k, v of list when not v._time
					list[k] =
						_time: settings.time
						_value: v

				sets[field] = {type: '$push', value: {
					_time: settings.time
					_value: value
				}}

			when 'newest'
				sets[field] = {type: '$set', value: value}

			when 'oldest'
				if typeof old_value is 'undefined'
					sets[field] = {type: '$set', value: value}

			when 'min', 'max'
				if value is Math[mode].apply null, [value, old_value].map(Number).filter((x) -> ! isNaN x)
					sets[field] = {type: '$set', value: value}

			when 'push'
				orig = old_value or []
				orig = [] if not Array.isArray orig
				list = orig.concat value
				sets[field] = {type: '$push', value: value}

			when 'push_unique'
				sets[field] = {type: '$addToSet', value: value}

	return {fact: new_fact, updates: sets}
