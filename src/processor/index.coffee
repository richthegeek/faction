console.log 'Starting processor'

accounts = {}
global.loadAccount = (accountID, next) ->
	if accounts[accountID]?
		return next null, accounts[accountID]

	new Account_Model () ->
		accounts[accountID] = @

		@load {_id: accountID}, (err, found) ->
			if err or not found
				return err or 'No such account: ' + accountID

			mongodb.open @dbname(), null, config.mongo.host, config.mongo.port, (err, db) =>
				@database = db
				next err, @

# promote delayed jobs
jobs.promote()

# execute all known job types
async = require 'async'
fs = require 'fs'
path = require 'path'
exec = require('child_process').exec

jobsPath = path.resolve __dirname, './jobs'

processJobs = (type, ready) ->
	jobPath = jobsPath + '/' + type

	processor = require jobPath
	multi = Math.max(processor.concurrency | 0, 1)

	console.log "Processing #{multi}x '#{type}' tasks"

	jobs.process type, multi, (job, complete) ->
		start = new Date
		processor job, (err, result) ->
			end = new Date
			stats.increment "kue.#{type}", 1
			stats.timing "kue.#{type}", (end - start)
			console.log '+', type, (end - start) + 'ms', job.data.title

			if err
				console.error '!', type, job.data.title, err
				job.log err

			complete()

	ready()

async.each fs.readdirSync(jobsPath), processJobs

