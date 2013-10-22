async = require 'async'
_ = require 'underscore'
soap = require 'soap'

# error generator closure
error = do ( ) ->
	errorMessages =
		'invalidOptions': 'Invalid options. Options must meet the following conditions:'
		'notInitilaised': 'Client not initilaised. Make sure you run this.init( cb )'
		'notLoggedIn': 'Client not authenticated. Check credentials and reinitialise'
		'noDatabase': 'No database selected. Please use this.selectDb to select one'
		'noId': 'No identifier specified.'
		'emptyFields': 'No fields specified.'
	( code, extra ) ->
		'code': code
		'message': errorMessages[code]
		'extraInfo': extra ? undefined

###
# Copernica Field Definitions
# name - Name of the field
# type - Type of the field
# value - Default value
# display - display on overview pages
# ordered - field order on overview pages
# length - field length
# textlines - number of text lines
# hidden - is field hidden
#
# what else? who knows...
###
collections =
	'Visits':
		'Start_time':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
		'Length_of_visit':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
		'Number_of_pages_visited':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
		'Session_ID':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
	'Pages':
		'Page_title':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 255
			'textlines': 1
			'hidden': false
			'index': true
		'Page_URL':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 255
			'textlines': 1
			'hidden': false
			'index': true
		'Time':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
		'visit_id':
			'type': 'integer'
			'value': 0
			'display': true
			'ordered': false
			'hidden': false
			'index': true
		'pageview_id':
			'type': 'integer'
			'value': 0
			'display': true
			'ordered': false
			'hidden': false
			'index': true
	'Links':
		'Link_URL':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 255
			'textlines': 1
			'hidden': false
			'index': true
		'Link_title':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 255
			'textlines': 1
			'hidden': false
			'index': true
		'Time':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
	'Forms':
		'FormName':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 255
			'textlines': 1
			'hidden': false
			'index': true
		'Time':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
		'FillID':
			'type': 'integer'
			'value': 0
			'display': true
			'ordered': false
			'hidden': false
			'index': true
	'Downloads':
		'DownloadName':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 255
			'textlines': 1
			'hidden': false
			'index': true
		'Time':
			'type': 'datetime'
			'value': ''
			'display': true
			'ordered': false
			'hidden': false
			'index': true
			'empty': true # TODO: is this right?
		'DownloadID':
			'type': 'integer'
			'value': 0
			'display': true
			'ordered': false
			'hidden': false
			'index': true
		'AutoCamp':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true

###
# Copernica Base Client
###
class Copernica_Base
	constructor: ( options = {}, callback ) ->
		defaults =
			'state': {}
			'url': 'http://mailmanager.livelinknewmedia.com/'
			'credentials':
				'username': null
				'account': null
				'password': null
			'database': null

		if typeof options is 'function'
			callback = options
			options = {}

		@options = _.extend defaults, options

		for key, val of @options.state
			@[key] = val

		if typeof callback is 'function'
			@init callback

	# Initialises the client and logs in
	init: ( callback ) ->
		async.waterfall [
			createClient = ( next ) =>
				if @client?
					next null, @client
				else
					soap.createClient "#{@options.url}?SOAPAPI=WSDL", next

			login = ( @client, next ) =>
				if @cookies?
					next null, '_trakapo_alreadyGotCookies', 'yolo'
				else
					client.login { 'parameters': @options.credentials }, next

			saveCredentials = ( data, response, next ) =>
				if data is '_trakapo_alreadyGotCookies'
					next null, @cookies
				else
					# TODO: check for DONE

					cookies = @client.lastResponseObj.headers['set-cookie']
					outCookies = []

					for cookie in cookies when 'soap_' is cookie.substr 0, 5
						outCookies.push cookie

					next null, outCookies

			selectDatabase = ( @cookies, next ) =>
				if @currentDB?
					next null, @
				else if @options.database?
					@selectDB @options.database, next
				else
					next null, @

		], ( err, obj ) =>
			callback err, obj
		@

	# Selects the DB to use
	selectDB: ( identifier, callback ) ->
		@request 'Account_database',
			{ 'identifier': identifier },
			{ 'noDb': true }, ( err, data ) =>
				@currentDB = data.result.database
				callback err, @
		@

	# Get a list of collections
	# TODO: DRY Search
	# TODO: move collection stuff out into other classes
	getCollections: ( callback ) ->
		params =
			'allproperties': true

		@request 'Database_collections', params, ( err, data ) ->
			callback err, [].concat data.result.items.collection

	# Create a collection
	createCollection: ( name, callback ) ->
		params =
			'name': name

		@request 'Database_createCollection', params, ( err, data ) ->
			callback err, data.result.collection

	# Create a collection
	removeCollection: ( id, callback ) ->
		params =
			'id': id

		@request 'Collection_remove', params, ( err, data ) ->
			if err or data.result.value isnt '1'
				callback err or 'Unknown error'
			else
				callback err, @

	createCollectionField: ( definition, callback ) ->
		# TODO: verify

		@request 'Collection_createField', definition, ( err, data ) ->
			callback err, data.result.collectionfield

	# Submit request and provide login credentials
	request: ( method, params = {}, options = {}, callback ) ->
		if 'function' is typeof params
			callback = params
			params = {}
		else if 'function' is typeof options
			callback = options
			options = {}

		if not @client?
			return callback error 'notInitilaised'
		if not @cookies?
			return callback error 'notLoggedIn'

		# if no id, add db id
		if not options.noDb
			if not @currentDB?
				return callback error 'noDatabase'
			params.id ?= @currentDB.id

		@client[method] { 'parameters': params }, callback,
			'headers':
				'Cookie': @cookies.join ';'

		@

###
# Simple Copernica Profile Model
###
class Copernica_Profile extends Copernica_Base
# Public
	constructor: ( options = {}, callback ) ->
		defaults = {}

		# copernica method names
		@soapMethods ?=
			'search': 'Database_searchProfiles'
			'create': 'Database_createProfile'
			'update': 'Profile_updateFields'
			'remove': 'Profile_remove'
		@returnProperties ?=
			'search': 'profile'
			'create': 'profile'

		if typeof options is 'function'
			callback = options
			options = {}

		super _.extend( defaults, options ), callback

	profile: ( id, fieldsToAdd = {}, callback, subprofileOptions = false ) ->
		async.waterfall [
			loadProfile = ( next ) =>
				@_search id, subprofileOptions or {}, next

			createIfNeeded = ( profile, next ) =>
				if profile.length is 0
					@_create _.extend( id, fieldsToAdd ), subprofileOptions or {}, ( err, data ) ->
						next err, data
				else
					profile = profile.shift( )
					profile._fields = {}
					for row in [].concat profile.fields.pair
						if fieldsToAdd[row.key]?
							profile._fields[row.key] = fieldsToAdd[row.key]
						else
							profile._fields[row.key] = row.value

					@_update profile.id, fieldsToAdd, ( err, data ) ->
						# TODO: verify success
						next err, profile

		], ( err, profile ) =>
			if not subprofileOptions
				@currentProfile = profile
				callback err, @
			else
				callback err, profile

	subprofile: ( id, fieldsToAdd = {}, options = {}, callback ) ->
		opts =
			'state':
				'client': @client
				'cookies': @cookies
				'currentDB': @currentDB
				'currentProfile': @currentProfile

		new Copernica_Subprofile opts, ( err, obj ) ->
			obj.profile id, fieldsToAdd, callback, _.extend options,
				'id': opts.state.currentProfile.id

# 'Private'
	# verfiy _search query
	_search_verify: ( query ) ->
		if not ( query.user_id? or query.email? )
			return error 'invalidOptions', 'Must contain either "user_id" or "email"'
		return false

	# Search for a profile, query should be 'user_id' or 'email'
	_search: ( query, options = {}, callback ) ->
		if typeof options is 'function'
			callback = options
			options = {}

		if err = @_search_verify query
			return callback err

		params =
			'allproperties': true
			'requirements': []
		params = _.extend params, options

		for key, val of query
			params.requirements.push
				'fieldname': key
				'casesensitive': false
				'operator': '='
				'value': val

		@request @soapMethods.search, params, ( err, data ) =>
			data = [].concat data.result.items[@returnProperties.search]
			for row in data
				data.fields?.pair = [].concat data.fields.pair
			callback err, data

	# verfiy _create fields
	_create_verify: ( fields ) ->
		if not fields.user_id or not fields.email
			return error 'invalidOptions', 'Must contain at least "user_id" and "email"'
		return false

	# Create a profile. fields must contain at least 'user_id' and 'email'
	_create: ( fields, options = {}, callback ) ->
		if typeof options is 'function'
			callback = options
			options = {}

		if err = @_create_verify fields
			callback err

		# https://www.copernica.com/en/support/apireference/Database_createProfile
		params =
			'fields':
				'pair': []
		params = _.extend params, options

		for key, value of fields
			params.fields.pair.push
				'key': key
				'value': value

		# TODO: output without the shitty key pair stuff
		@request @soapMethods.create, params, ( err, data ) =>
			data.result[@returnProperties.create].fields?.pair = [].concat data.result[@returnProperties.create].fields.pair
			callback err, data.result[@returnProperties.create]

	# Update fileds in a profile, id must contain a profile id.
	_update: ( id, fields, callback ) ->
		if not id?
			return callback error 'noId'
		if Object.keys( fields ).length is 0
			return callback error 'emptyFields'

		# https://www.copernica.com/en/support/apireference/Profile_updateFields
		params =
			'id': id
			'timestamp': +new Date / 1000
			'fields':
				'pair': []

		for key, value of fields
			params.fields.pair.push
				'key': key
				'value': value

		@request @soapMethods.update, params, ( err, data ) =>
			if err or data.result.value isnt '1'
				callback err or 'Unknown error'
			else
				callback err, @

	# Remove a profile
	_remove: ( id, callback ) ->
		if not id?
			return callback error 'noId'

		params =
			'id': id

		@request @soapMethods.remove, params, ( err, data ) ->
			if err or data.result.value isnt '1'
				callback err or 'Unknown error'
			else
				callback err, @

###
# Simple Copernica SubProfile model
###
class Copernica_Subprofile extends Copernica_Profile
# Public
	constructor: ( options = {}, callback ) ->
		defaults = {}

		# copernica method names
		@soapMethods ?=
			'search': 'Profile_searchSubProfiles'
			'create': 'Profile_createSubProfile'
			'update': 'SubProfile_updateFields'
			'remove': 'SubProfile_remove'

		@returnProperties ?=
			'search': 'subprofile'
			'create': 'subprofile'

		if typeof options is 'function'
			callback = options
			options = {}

		super _.extend( defaults, options ), callback

# 'Private'
	# verfiy _search query
	_search_verify: ( query ) ->
		# if not query.collection?
		# 	return error 'invalidOptions', 'Must contain "collection" and an id field'
		return false

	# verfiy _create fields
	_create_verify: ( fields ) ->
		# if not fields.collection?
		# 	return error 'invalidOptions', 'Must contain "collection" and an id field'
		return false

###
# Trakapo HookService
###
module.exports =
	'setup': ( options, callback ) ->
		async.waterfall [
			connectToCopernica = ( next ) ->
				new Copernica_Base options, next

			getCurrentCollections = ( copernica, next ) ->
				copernica.getCollections ( err, currentCollections ) ->
					console.log err, currentCollections

					next err, currentCollections, copernica

			addMissingCollections = ( currentCollections, copernica, next1 ) ->
				return console.log currentCollections
				async.map Object.keys( collections ), ( ( collectionName, next2 ) ->
					# Check it doesn't exist already
					for row in currentCollections when collectionName is row.name
						return next2 null

					async.waterfall [
						createCollection = ( next3 ) ->
							copernica.createCollection collectionName, next3

						createFields = ( collection, next3 ) ->
							fields = collections[collectionName]

							async.map fields, ( ( fieldName, next4 ) ->
								params = fields[fieldName]
								params.name = fieldName
								params.id = collection.id

								copernica.createField params, next4
							), next3
					], next2
				), next1

		], ( err, results ) ->
			callback err

	'exec': ( options, data, callback ) ->
		async.map data, ( ( profile, next ) ->
			async.waterfall [
				loadCopernica = ( next1 ) ->
					copProfile = new Copernica_Profile options, next1

				updateProfile = ( obj, next1 ) ->
					# TODO: device info
					obj.profile { 'user_id': profile._id, 'email': profile.email },
						{ 'score': profile.score, 'name': profile.name }, next1

				addSessions = ( obj, next1 ) ->
					async.map profile.devices, ( ( device, next2 ) ->
						async.map device.sessions, ( ( session, next3 ) ->
							obj.subprofile { 'session_id': session._id },
								{ 'did': session.did 'actions': session.actions }, next3
						), next2
					), next1
			], next
		), ( err, results ) ->
			callback err, results

	'_classes':
		'Copernica_Base': Copernica_Base
		'Copernica_Profile': Copernica_Profile
		'Copernica_Subprofile': Copernica_Subprofile