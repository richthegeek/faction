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

# Download file extensions. used to determine if a page action is a download
downloadFileTypes = ['pdf', 'zip']

###
# Turns into a human readable time. input in seconds
###
timeNouns = ['seconds', 'minutes', 'hours', 'days']
humanTime = ( x ) ->
	time = []
	time.push Math.round ( x /= 60 ) % 60
	time.push Math.round ( x /= 60 ) % 60
	time.push Math.round ( x /= 24 ) % 24
	time.push Math.round x

	index = time.length
	while time[--index] is 0 and index > 1
		true

	"#{time[index]} #{timeNouns[index]}, #{time[index - 1]} #{timeNouns[index - 1]}"

###
# Converts an ISO formatted date into Copernica Style
###
ISOtoCopernica = ( str ) -> str.replace( 'T', ' ' ).replace( '.000Z', '' )

###
# Simple hash code of a string
###
String.prototype.hashCode = ->
    hash = 0
    return hash if @length is 0
    for i in [0...@length]
        chr = @charCodeAt i
        hash = ( ( hash << 5 ) - hash ) + chr
        hash |= 0 # Convert to 32bit integer
    hash

###
# Creates an ID from an ISO date and a piece of identifying information
###
actionId = ( time, identifier ) ->
	time = ISOtoCopernica( time ).replace( ':', '' ).replace( ' ', '' ).replace( '-', '' )
	identifier = identifier.hashCode( )
	"#{time}-#{identifier}"

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
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
			'hidden': false
			'index': true
		'pageview_id':
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
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
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
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
			'type': 'text'
			'value': ''
			'display': true
			'ordered': false
			'length': 50
			'textlines': 1
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
			# 'url': 'http://soapweb6.copernica.nl'
			'url': 'http://soap.copernica.com'
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

					if not @client.lastResponseObj?.headers?
						console.log 'malformed lastResponseObj', data, response
						console.log data.headers
						console.log response.headers
						console.log @client.lastResponseObj?.headers
						console.log @client.lastResponse?.headers
						next 'malformed lastResponseObj'

					cookies = @client.lastResponseObj?.headers?['set-cookie'] or []
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
				if not data.result?.database?
					callback 'No database'
				else
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
				# console.log '~~ load profile'
				@_search id, subprofileOptions or {}, next

			createIfNeeded = ( profile, next ) =>
				# console.log '~~ create if needed'
				profile = [].concat profile
				if profile.length is 0 or profile[0] is undefined or Object.keys( profile[0] ).length is 0
					# console.log '~~ create'
					@_create _.extend( id, fieldsToAdd ), subprofileOptions or {}, ( err, data ) ->
						# console.log '~~ create cb'
						next err, data
				else
					# console.log '~~ update', profile, profile[0]
					profile = profile.shift( )
					profile._fields = {}
					for row in [].concat profile.fields.pair
						if fieldsToAdd[row.key]?
							profile._fields[row.key] = fieldsToAdd[row.key]
						else
							profile._fields[row.key] = row.value

					@_update profile.id, fieldsToAdd, ( err, data ) ->
						# console.log '~~ update cb'
						# TODO: verify success
						next err, profile

		], ( err, profile ) =>
			# console.log '~~ do callback'
			if not subprofileOptions
				@currentProfile = profile
				callback err, @
			else
				callback err, profile

	subprofile: ( id, fieldsToAdd = {}, options = {}, callback ) ->
		# console.log '** in subprofile'
		opts =
			'state':
				'client': @client
				'cookies': @cookies
				'currentDB': @currentDB
				'currentProfile': @currentProfile

		new Copernica_Subprofile opts, ( err, obj ) ->
			# console.log '** init'
			obj.profile id, fieldsToAdd, callback, _.extend options,
				'id': opts.state.currentProfile.id
			# console.log '** in post subprofile'

# 'Private'
	# verfiy _search query
	_search_verify: ( query ) ->
		# if not ( query.user_id? or query.email? )
			# return error 'invalidOptions', 'Must contain either "user_id" or "email"'
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
			'requirements':
				'requirement': []
		params = _.extend params, options

		for key, val of query
			params.requirements.requirement.push
				'fieldname': key
				'casesensitive': false
				'operator': '='
				'value': val

		@request @soapMethods.search, params, ( err, data ) =>
			if data?.result?.items?
				if data?.result?.items?[@returnProperties.search]?
					data = [].concat data.result.items[@returnProperties.search]
					for row in data
						data.fields?.pair = [].concat data.fields.pair
					callback err, data
				else
					callback err, {}
			else
				console.log 'Invalid search result', data
				callback 'Invalid search result'

	# verfiy _create fields
	_create_verify: ( fields ) ->
		# if not fields.user_id or not fields.email
			# return error 'invalidOptions', 'Must contain at least "user_id" and "email"'
		return false

	# Create a profile. fields must contain at least 'user_id' and 'email'
	_create: ( fields, options = {}, callback ) ->
		if typeof options is 'function'
			callback = options
			options = {}

		if err = @_create_verify fields
			return callback err

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
					next err, currentCollections, copernica

			addMissingCollections = ( currentCollections, copernica, next1 ) ->
				async.map Object.keys( collections ), ( ( collectionName, next2 ) ->
					# Check it doesn't exist already
					for row in currentCollections when collectionName is row?.name
						return next2 null

					async.waterfall [
						createCollection = ( next3 ) ->
							copernica.createCollection collectionName, next3

						createFields = ( collection, next3 ) ->
							fields = collections[collectionName]

							async.map Object.keys( fields ), ( ( fieldName, next4 ) ->
								params = fields[fieldName]
								params.name = fieldName
								params.id = collection.id

								copernica.createCollectionField params, next4
							), next3
					], next2
				), ( err, results ) ->
					next1 err, results, copernica
		], callback

	'exec': ( hook, data, callback ) ->
		options = hook.options
		# TODO: generalise
		data = [].concat data

		async.map data, ( ( profile, next ) ->
			async.waterfall [
				loadCopernica = ( next1 ) ->
					copProfile = new Copernica_Profile options, next1

				updateProfile = ( copernica, next1 ) ->

					id_fields =
						'Email': profile.email

					data_fields =
						'uid': profile._id
						'LeadScore': profile.score.score or 0
					# TODO: device info
					copernica.profile id_fields, data_fields, next1

				getCollections = ( copernica, next1 ) ->
					copernica.getCollections ( err, collections ) ->
						next1 err, copernica, collections

				addSessions = ( copernica, collections, next1 ) ->
					collectionsMap = {}
					for i, row of collections
						collectionsMap[row.name] = i
					# console.log 'collections map', collectionsMap

					# TODO: should I use mapSeries?
					async.map profile.devices, ( ( device, next2 ) ->
						async.map device.sessions, ( ( session, next3 ) ->
							# TODO: this is pretty hacky. need an ID on actions
							pvid = 0
							async.map session.actions, ( ( action, next4 ) ->
								# console.log "\n\n", action

								# TODO: this is interim code, remove it at some point
								if action._value.type is 'page' and action._value.url.slice( -3 ) in downloadFileTypes
									action._value.type = 'download'

								switch action._value.type
									when 'page'
										# console.log 'page'
										id =
											'pageview_id': actionId action._time, action._value.url
											'visit_id': session._id
										fields =
											'Page_title': action._value.title or ''
											'Page_URL': action._value.url
											'Time': ISOtoCopernica action._time
										options =
											'collection': collections[collectionsMap['Pages']]
									when 'download'
										# console.log 'download'
										id =
											'DownloadID': actionId action._time, action._value.url
										fields =
											'DownloadName': action._value.url
											'Time': ISOtoCopernica action._time
										options =
											'collection': collections[collectionsMap['Downloads']]
									when 'form'
										# console.log 'form'
										id =
											'fillID': actionId action._time, action._value.form_id
										fields =
											'FormName': action._value.form_id
											'Time': ISOtoCopernica action._time
										options =
											'collection': collections[collectionsMap['Forms']]
									else
										# console.log 'else', action._value.type
										return next4( )

								options.id = copernica.currentProfile.id

								copernica.subprofile id, fields, options, next4

							), ( err, data ) ->
								times = []
								for row in session.actions when row._time
									times.push new Date row._time

								finishSession = ( err ) ->
									return next3 err if err

									id =
										'Session_ID': session._id
									fields =
										'Length_of_visit': humanTime ( Math.max.apply( Math, times ) - Math.min.apply( Math, times ) ) / 1000
										'Number_of_pages_visited': session.actions.length
										'Start_time': ISOtoCopernica session.actions[0]._time
									options =
										'collection': collections[collectionsMap['Visits']]
									copernica.subprofile id, fields, options, next3

								# Handle baskets if they exist
								if basket = session.basket
									# construct the object to be sent to copernica
									order =
										'order_status': 'basket'
										'date': ISOtoCopernica session._updated
										'total': basket.prices.ordertotal ? 0
									basket_out =
										'value': basket.prices.subtotal ? 0
										'Number_of_items': basket.line_items.length
										'status': 'live'

									max = 0
									if basket.stage?
										for key, val of basket.stage when Math.max( max, val = new Date( val ) ) is val
											max = val
											order.order_status = key

									if order.status is 'completed'
										basket_out.status = 'ordered'
									else if ( new Date( ) - new Date session_updated ) > 180000
										basket_out.status = 'abandoned'

									# Do the actual sending
									# TODO: could this be parallel?
									async.series [
										doOrder = ( next4 ) ->
											id =
												'order_id': session._id
											options =
												'collection': collections[collectionsMap['Orders']]
											copernica.subprofile id, order, options, next4

										doBasket = ( next4 ) ->
											id =
												'session_id': session._id
											options =
												'collection': collections[collectionsMap['Basket']]
											copernica.subprofile id, basket_out, options, next4

										doLineItems = ( next4 ) ->
											# DEAD LEGACY ONLY CODE
											# TODO: come up with a better way to do this
											options =
												'collection': collections[collectionsMap['Products']]
											id =
												'orderID': session._id

											doLineItem = ( item, next45 ) ->
												urlparts = item.product_url.split '/'
												id.SKU = urlparts[4]
												product =
													'Name': item.name
													'Price': item.price
													'Category': urlparts[5]
												copernica.subprofile id, product, options, next45

											async.mapSeries basket.line_items, doLineItem, next4
									], finishSession
								else
									finishSession( )
						), next2
					), ( err, results ) ->
						meaningfulResult =
							'profile_id': profile._id
							'copernica_id': copernica.currentProfile.id
							'time': +new Date

						next1 err, meaningfulResult, copernica
			], next
		), callback

	'_classes':
		'Copernica_Base': Copernica_Base
		'Copernica_Profile': Copernica_Profile
		'Copernica_Subprofile': Copernica_Subprofile
