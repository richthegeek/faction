async = require 'async'
Cache = require 'shared-cache'

module.exports =
	disabled: false
	concurrency: 1
	timeout: 10000

	exec: (job, done) ->
		account = null
		accountID = job.data.account
		time = new Date parseInt job.created_at
		type = job.data.data.fact_type

		loadAccount accountID, (err, acc) ->
			account = acc

			new Fact_deferred_Model account, type, (err) ->
				@table.aggregate {$group: {_id: null, ids: $push: '$_id'}}, (err, result) ->
					ids = result[0].ids
					insert = (id, next) =>
						Fact_deferred_Model.markUpdated id, type, account, next

					console.log 'Fact_update_all creating ' + ids.length + ' jobs'
					async.map ids, insert, done
