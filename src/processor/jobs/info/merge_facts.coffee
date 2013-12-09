xtend = require 'xtend'
traverse = require 'traverse'
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
	for field, mode of settings.field_modes
		if mode.eval
			continue

		value = mid_fact[field]
		old_value = old_fact[field]

		delete sets[field]
		switch mode
			when 'inc'
				a = Number(value) or 1
				b = Number(old_value) or 0
				sets[field] = {type: '$inc', value: a}

			when 'inc_day', 'inc_week', 'inc_month', 'inc_year'
				moment = require 'moment'
				formats =
					inc_day: 'YYYY-MM-DD'
					inc_week: 'YYYY-WW'
					inc_month: 'YYYY-MM'
					inc_year: 'YYYY'
				key = moment().format formats[mode]
				value = Number(value) or 1
				sets[field + '.' + key] = {type: '$inc', value: value}

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

			when 'oldest'
				if typeof old_value is 'undefined'
					sets.$set ?= {}
					sets.$set[field] = value
					sets[field] = {type: '$set', value: value}

			when 'min', 'max'
				value = Math[mode].apply null, [value, old_value].map(Number).filter((x) -> ! isNaN x)
				sets[field] = {type: '$set', value: value}

			when 'push'
				orig = old_value or []
				orig = [] if not Array.isArray orig
				list = orig.concat value
				sets[field] = {type: '$push', value: value}

			when 'push_unique'
				sets[field] = {type: '$addToSet', value: value}

	return {fact: new_fact, updates: sets}
