check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class Account_Model extends Model

	constructor: (callback) ->
		super 'faction', 'accounts', callback

	_spawn: (callback) ->
		new @constructor callback

	dbname: () ->
		return 'faction_account_' + @data._id

	@route = (req, res, next) ->
		new Account_Model () ->
			req.model = @
			next()

	setup: () ->
		new Action_Model @, () -> @setup()
		new Actionresult_Model @, () -> @setup()
		new Condition_Model @, () -> @setup()
		# fact has a "type" parameter for collection routing, don't worry about it.
		new Fact_Model @, 'setup', () -> @setup()
		new Factsettings_Model @, () -> @setup()
		new Hook_Model @, () -> @setup()
		new Info_Model @, () -> @setup()
		new Infomapping_Model @, () -> @setup()

	create: (info, callback) ->
		if typeof info is 'function'
			callback = info
			info = {}

		@data = {}

		# semi-sequential number as an ID.
		base = new Date().getTime().toString() + Math.round 1000 * do Math.random
		@data._id = crypto.createHash('sha1').update(base).digest('hex').substring(0, 16)


		# generate a key, and set the contact information
		@setContact info, (err) =>
			if err
				return callback err

			@generateKey 'primary', {parent: null, endpoints: ['.*'], secure: true}, (e, a, b) =>
				@setup()
				callback e, a, b

	setContact: (info, callback) ->
		# copy info over to @data
		info = info.contact or info

		@data.contact ?= {}
		for k, v of info when v
			@data.contact[k] = v

		# save
		@save callback

	validate: (data, callback) ->
		data.contact ?= {}
		if not data.contact.name
			return callback 'Contact name (body property: "name") must be non-empty'

		if not data.contact.email
			return callback 'Contact email (body property: "email") must be valid'

		if not data.contact.email.match /^[a-z0-9_.+-]+@[a-z0-9-]+\.[a-z0-9-.]+$/i
			return callback 'Contact email must be valid.'

		callback()

	generateKey: (name, options, callback) ->
		@data.keys ?= {}

		parent = options.parent ? null
		endpoints = options.endpoints ? ['.*']
		secure = options.secure ? true

		# check that the parent exists!
		if parent and not @data.keys[parent]?
			return callback 'The specified parent does not exist.'

		# ensure that the endpoints are valid regular expressions...
		for regex in endpoints
			reg = new RegExp regex

		@data.keys[name] = {
			name: name
			parent: parent
			public: @data._id + crypto.createHash('sha1').update(Math.random() + +new Date() + 'public').digest('hex').substring(0, 16)
			private: crypto.createHash('sha512').update(Math.random() + +new Date() + 'private').digest('hex'),
			endpoints: endpoints
			secure: !! secure
		}

		@save (err) =>
			callback err, @data.keys[name]

	deleteKey: (name, callback) ->
		keys = @getChildKeys name
		for key in keys
			delete @data.keys[key.name]

		if (1 for k of @data.keys when k).length is 0
			throw 'Deleting this key would result in this account having no keys. Aborting!'

		@save (err) ->
			callback err, keys


	getChildKeys: (parent, andSelf = true, limit = 100) ->
		# disallow recursive death
		if limit is 0
			return []

		children = []

		if andSelf
			children.push @data.keys[parent]

		for name, key of @data.keys when key.parent is parent
			children = children.concat @getChildKeys key.name, true, limit - 1

		return children

	export: (key) ->
		data = super
		if key
			keys = @getChildKeys key.name
			data.keys = {}
			data.keys[key.name] = key for key in keys
		return data
