async = require 'async'
moment = require 'moment'
{getColumn, setColumn, deleteColumn} = require '../info/column_ops'

module.exports = (fact, key, settings, context, callback) ->

	async.waterfall [

		(next) ->
			fact.withMap [], settings.map, context, (err, map) ->
				next null, map

		(map, next) ->
			(map[k] = map[k] ? v) for k, v of context
			fact.data.eval settings.eval, map, (err, res) ->
				res = res ? settings.default ? null
				next null, res

		(new_value, next) ->
			# merge
			grouped_modes = ['newest', 'oldest', 'inc', 'min', 'max']

			mode = settings.mode
			field = key
			formats =
				day: 'YYYY-MM-DD'
				week: 'YYYY-WW'
				month: 'YYYY-MM'
				year: 'YYYY'
			if format = formats[settings.grouping]
				if mode in grouped_modes
					date = moment().format(format)
					eval_field = field + '["' + date + '"]'
					field = field + '.' + date

			fact.data.eval 'this.' + eval_field, (err, old_value) ->
				result =
					key: field
					value: new_value
					mode: 'set'

				if mode is 'inc'
					result.value = Number(new_value) or 1
					result.mode = 'inc'

				if mode is 'inc_map'
					result.key = key + '.' + value.replace /\./g, '%2E'
					result.value = 1
					result.mode = 'inc'

				if mode in ['min', 'max']
					if new_value isnt Math[mode].apply null, [new_value, old_value].map(Number).filter((x) -> ! isNaN x)
						# if it isnt changed, set to null to stop a write on this column
						result = null

				if mode is 'oldest'
					if old_value
						# if there is already a value, set to null to stop write on this col
						result = null

				if mode in ['push', 'push_unique', 'all']
					result.key = key
					result.mode = 'push'

					if mode is 'push_unique'
						result.mode = 'addToSet'

					if mode is 'all'
						result.value = {
							_time: fact._updated,
							_value: new_value
						}

				if settings.latest and mode in grouped_modes
					# set a key.latest value if requested. If "latest" is a string, use that as the key.
					name = ('string' is typeof settings.latest and settings.latest) or 'latest'
					result = [result, {
						key: key + '.' + name
						value: result.value
						mode: result.mode
					}]

				next null, result

		(result, next) ->
			if result
				for row in [].concat.apply [], result
					fact.data.set row.key, row.value
			next null, result

	], callback

