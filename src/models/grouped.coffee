async = require 'async'
module.exports = class Grouped_Model extends Array

	constructor: (type, items, callback) ->
		iter = (item, next) ->
			type._spawn () ->
				@import item, () =>
					next null, @

		async.map items, iter, (err, items) =>
			for item in items
				@push item
			callback.call @, err, @

	export: () ->
		item.export() for item in @

	toJSON: () ->
		item.toJSON() for item in @
