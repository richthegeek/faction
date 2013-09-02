check = require('validator').check
crypto = require 'crypto'
Model = require './model'

module.exports = class Account extends Model

	constructor: (callback) ->
		super 'core', 'accounts', callback

	dbname: () ->
		return 'account_' + @data._id

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

			@generateKey 'primary', null, callback

	setContact: (info, callback) ->
		# copy info over to @data
		info = info.contact or info

		@data.contact ?= {}
		for k, v of info when v
			@data.contact[k] = v

		# validate contact information.
		check(@data.contact.name, {
			notNull: 'Contact name (body property: "name") must be non-empty',
			notEmpty: 'Contact name (body property: "name") must be non-empty'
		}).notNull().notEmpty()

		check(@data.contact.email, {
			notNull: 'Contact email (body property: "email") must be non-empty',
			isEmail: 'Contact email (body property: "email") must be valid'
		}).notNull().isEmail()
		console.log '.'

		# save
		@save callback

	generateKey: (name, parent, callback) ->
		@data.keys ?= {}

		# check that the parent exists!
		if parent and not @data.keys[parent]?
			return callback 'The specified parent does not exist.'

		@data.keys[name] = {
			name: name
			parent: parent
			public: @data._id + crypto.createHash('sha1').update(Math.random() + +new Date() + 'public').digest('hex').substring(0, 16)
			private: crypto.createHash('sha512').update(Math.random() + +new Date() + 'private').digest('hex')
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
