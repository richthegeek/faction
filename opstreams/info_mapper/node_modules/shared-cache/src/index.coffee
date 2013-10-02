redis = require 'redis'
module.exports = class Cache

	constructor: (@key, auto_update, update_callback) ->

		Cache.singletons ?= {}
		Cache.singletons[key] = @

		Cache.RedisIn ?= redis.createClient()
		Cache.RedisOut ?= redis.createClient()
		ps = Cache.RedisIn

		ps.subscribe "dcache:#{@key}"
		ps.on "message", (channel, message) =>
			if channel is "dcache:#{@key}"
				if message.toString() is "1"
					@stale false
				else
					@set JSON.parse(message), false

		if typeof auto_update is 'function'
			update_callback = auto_update
			auto_update = true

		@data = false
		@is_stale = true
		@queue = []
		@auto_update = auto_update
		@update_callback = update_callback

		if auto_update
			@update () -> null

	@create = (key, auto_update, update_callback) ->
		Cache.singletons ?= {}
		Cache.singletons[key] ?= new Cache key, auto_update, update_callback
		# turn on auto_update if it's defined
		Cache.singletons[key].auto_update = Cache.singletons[key].auto_update or auto_update
		# if the previous instance was not a getter, define the update callback...
		Cache.singletons[key].update_callback = Cache.singletons[key].update_callback or update_callback

		return Cache.singletons[key]

	get: (callback) ->
		if not @is_stale
			# use nextTick to prevent Zalgo from escaping
			process.nextTick () => callback null, @data, true
			return @data

		@update callback
		return @data

	set: (data, broadcast = true) ->
		@data = data
		@is_stale = false

		if broadcast
			Cache.RedisOut.publish "dcache:#{@key}", JSON.stringify data

	update: (callback) ->
		if @queue.length is 0
			fallback = (key, next) -> next 'No update function defined!'
			(@update_callback or fallback) @key, (err, data) =>
				if not err
					@is_stale = false
				@data = data
				while fn = @queue.shift() when fn.call
					fn err, data, false
		@queue.push callback

	stale: (broadcast = true) ->
		@is_stale = true

		if @auto_update
			@update () -> null

		if broadcast
			Cache.RedisOut.publish "dcache:#{@key}", 1
