module.exports = (stream, config, row) ->

	return {
		evaluate: config.models.fact.evaluate,
		interpolate: config.models.fact.interpolate,
		parseObject: config.models.fact.parseObject
	}
