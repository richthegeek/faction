console.log 'Starting processor'

accounts = {}
global.loadAccount = (accountID, next) ->

	if accounts[accountID]?
		return next null, accounts[accountID]

	new Account_Model () ->
		@load {_id: accountID}, (err, found) ->
			if err or not found
				return err or 'No such account: ' + accountID

			mongodb.open @dbname(), null, config.mongo.host, config.mongo.port, (err, db) =>
				accounts[accountID] = @
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

killSwitch = false
processing = 0

killProcessor = () ->
	killSwitch = true
	setInterval (() ->
		console.log processing
		if processing is 0
			process.exit 0
	), 100
	setTimeout (() ->
		process.exit 0
	), 5000

process.on 'SIGINT', () ->
	console.log 'Shutting down in 5 seconds due to SIGINT Ctrl-C'
	killProcessor()

processJobs = (type, ready) ->
	jobPath = jobsPath + '/' + type

	processor = require jobPath
	multi = Math.max(processor.concurrency | 0, 1)
	timeout = processor.timeout | 0
	disabled = (processor.disabled is true) or (processor.concurrency is 0)

	if disabled
		console.log "Skipping #{type} tasks"
		return ready()

	console.log "Processing #{multi}x '#{type}' tasks"

	times = []
	idle =false
	setInterval (() ->
		pad = (str, size = 5) ->
			str = str.toString()
			while str.length < size
				str = " " + str
			return str
		if times.length > 0

			sum = pad times.reduce (a, b) -> a + b
			max = pad times.reduce (a, b) -> Math.max(a, b)
			min = pad times.reduce (a, b) -> Math.min(a, b)
			mean = pad Math.round sum / times.length

			if (timeout > 0) and (mean > timeout)
				killSwitch = true
				console.log 'Killing in 5 seconds due to speed problems'
				killProcessor()

			percent = sum / (config.kue.interval * 10 ) # 100s / 1000i
			percent = Math.round percent

			console.log "+", pad(type, 15), pad(times.length), pad("#{percent}%"), [mean, min, max].join(" / ")
			idle = false
			times = []
		else
			if not idle
				console.log "`", pad(type, 15), 'idle'
			idle = true
	), (config.kue.interval * 1000)

	jobs.process type, multi, (job, complete) ->
		if killSwitch
			job.state 'inactive'
			job.save()
			return

		start = new Date
		processing++
		processor job, (err, result) ->
			end = new Date
			time = (end - start)
			stats.increment "kue.#{type}", 1
			stats.timing "kue.#{type}", time
			# console.log "+", type, "#{time}ms", job.data.title

			times.push time

			if err
				console.error '!', type, job.data.title, err
				job.log err

			processing--
			complete()

	ready()

async.each fs.readdirSync(jobsPath), processJobs

