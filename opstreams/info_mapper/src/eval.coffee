module.exports = (stream, config, row) ->

	async = require 'async'

	evaluate = (str, context, callback) ->
		context.isAsync = false
		context.async = (val = true) -> context.isAsync = val
		context.complete = (err, str) ->
			context.complete = () -> null
			process.nextTick () -> callback? err, str

		fn = () ->
			try
				`with(context) { str = eval(str) }`
			catch e
				return context.complete e, str

			if not context.isAsync
				context.complete null, str
				return str
			return null

		return do fn.bind {}

	###
	interpolate: evaluate demarcated sections of a string
	###
	interpolate = (str, context, callback) ->
		(str.match(/\#\{.+?\}/g) or []).forEach (section) =>
			str = str.replace section, evaluate section.slice(2, -1), context
		return str

	###
	parseObject: evaluate the object with this context, interpolating keys and evaluating leaves.
		Should transform an object like:
			"orders": "item", "order_#{item.oid}_value": "item.value"
		Into this:
			"orders": {oid: 42, value: 400}, "orders_42_value": 400
	###
	parseObject = (obj, context, callback) ->
		# interpolate keys
		obj = JSON.parse (JSON.stringify obj), (key, value) =>
			if Object::toString.call(value) is '[object Object]'
				for k, v of value
					delete value[k]
					k = interpolate k, context
					value[k] = v
			return value

		# collect leaves to evaluate
		nodes = []
		traverse = require 'traverse'
		traverse(obj).forEach (val) ->
			if @isLeaf
				@value = val
				nodes.push @

		iter = (node, next) =>
			evaluate node.value, context, (err, newval) =>
				next err, node.update newval, true

		async.each nodes, iter, () -> callback obj

	return {
		evaluate: evaluate,
		interpolate: interpolate,
		parseObject: parseObject
	}
