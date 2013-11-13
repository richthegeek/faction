assert = require 'assert'
async = require 'async'
copernica = require '../types/copernica'

suite 'copernica', ( ) ->
	@timeout 30000
	copernicaOptions =
		'credentials':
			'username': 'j.sanderson@livelinknewmedia.com'
			'password': 'Manch1793!'
			'account': 'Elliot UK'
		'database': 'TestDB'
		'state': {}
	ids = {}

	waitForId = ( id, callback ) ->
		fn = ( ) ->
			if ids[id]?
				callback ids[id]
			else
				setTimeout fn, 250
		setTimeout fn, 250

	test 'can connect to copernica', ( done ) ->
		options = copernicaOptions

		new copernica._classes.Copernica_Base options, ( err, obj ) ->
			assert.equal null, err
			assert.equal copernicaOptions.database, obj.currentDB.name

			# # Save details for futher tests
			# copernicaOptions =
			# 	'state':
			# 		'client': obj.client
			# 		'cookies': obj.cookies
			# 		'currentDB': obj.currentDB
			# copernicaBase = obj

			done( )

	test 'can create collection', ( done ) ->
		options = copernicaOptions

		new copernica._classes.Copernica_Base options, ( err, obj ) ->
			obj.createCollection 'testCollection', ( err, collection ) ->
				assert.equal null, err
				assert.equal 'testCollection', collection.name

				ids['collection'] = collection.id

				done( )

	test 'can add fields to collection', ( done ) ->
		waitForId 'collection', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Base options, ( err, obj ) ->
				options =
					'id': id
					'name': 'testField'
					'type': 'text'
					'value': ''
					'display': true
					'ordered': false
					'length': 255
					'textlines': 1
					'hidden': false
					'index': true

				obj.createCollectionField options, ( err, field ) ->
					assert.equal null, err
					assert.equal options.name, field.name
					assert.equal options.type, field.type
					assert.equal "#{options.display}", field.displayed
					assert.equal "#{options.ordered}", field.ordered
					assert.equal options.length, field.length
					assert.equal options.textlines, field.lines
					assert.equal "#{options.hidden}", field.hidden

					# TODO: index via api not working
					# assert.equal "#{options.index}", field.index

					done( )

	test 'can check collections', ( done ) ->
		options = copernicaOptions

		new copernica._classes.Copernica_Base options, ( err, obj ) ->
			obj.getCollections ( err, collections ) ->
				assert.equal null, err
				assert collections.length > 0

				for row in collections
					if row.name is 'testCollection'
						assert.equal 'testCollection', row.name

				done( )

	test 'can create profile', ( done ) ->
		options = copernicaOptions

		new copernica._classes.Copernica_Profile options, ( err, obj ) ->
			options =
				'user_id': '1'
				'email': 'testUser@trakapo.com'

			obj._create options, ( err, profile ) ->
				assert.equal null, err
				assert profile.fields.pair.length > 0

				for row in profile.fields.pair
					switch row.key
						when 'user_id'
							assert.equal options.user_id, row.value
						when 'email'
							assert.equal options.email, row.value

				ids['profile'] = profile.id
				done( )

	test 'can update profile', ( done ) ->
		waitForId 'profile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Profile options, ( err, obj ) ->
				options =
					'name': 'John Doe'

				obj._update id, options, ( err, obj ) ->
					assert.equal null, err

					done( )

	test 'can search for profile', ( done ) ->
		waitForId 'profile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Profile options, ( err, obj ) ->
				options =
					'email': 'testUser@trakapo.com'

				obj._search options, ( err, results ) ->
					assert.equal null, err
					assert results.length > 0

					for row in results
						for pair in row.fields.pair
							if pair.key is 'email' and pair.value is options.email
								assert true

					done( )

	test 'can create subprofile', ( done ) ->
		waitForId 'profile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Subprofile options, ( err, obj ) ->
				options =
					'id': id
					'collection':
						'id': ids['collection']

				fields =
					'testField': 'bar'

				obj._create fields, options, ( err, subprofile ) ->
					assert.equal null, err
					assert subprofile.fields.pair.length > 0

					for row in subprofile.fields.pair
						switch row.key
							when 'testField'
								assert.equal fields.testField, row.value

					ids['subprofile'] = subprofile.id
					done( )

	test 'can update subprofile', ( done ) ->
		waitForId 'subprofile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Subprofile options, ( err, obj ) ->
				options =
					'testField': 'bar'

				obj._update id, options, ( err, obj ) ->
					assert.equal null, err

					done( )

	test 'can search for subprofile', ( done ) ->
		waitForId 'subprofile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Subprofile options, ( err, obj ) ->
				options =
					'id': ids['profile']
					'collection':
						'id': ids['collection']

				fields =
					'testField': 'bar'

				obj._search fields, options, ( err, results ) ->
					assert.equal null, err
					assert results.length > 0

					for row in results
						for pair in row.fields.pair
							if pair.key is 'testField' and pair.value is fields.testField
								assert true

					done( )

	test 'can use profile combo method', ( done ) ->
		waitForId 'profile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Profile options, ( err, obj ) ->
				id =
					'email': 'testUser@trakapo.com'

				fieldsToUpdate =
					'user_id': '23'

				obj.profile id, fieldsToUpdate, ( err, obj ) ->
					assert.equal null, err
					assert.equal obj.currentProfile._fields.user_id, fieldsToUpdate.user_id

					done( )

	test 'can use subprofile combo method', ( done ) ->
		waitForId 'subprofile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Profile options, ( err, obj ) ->
				id =
					'testField': 'bar'

				fieldsToUpdate =
					'testField': 'baz'

				options =
					'collection':
						'id': ids['collection']

				obj.currentProfile ?= {}
				obj.currentProfile.id = ids['profile']

				obj.subprofile id, fieldsToUpdate, options, ( err, obj ) ->
					assert.equal null, err
					assert.equal obj._fields.testField, fieldsToUpdate.testField

					ids['delete_subprofile'] = 1

					done( )

	test 'can remove a subprofile', ( done ) ->
		waitForId 'delete_subprofile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Subprofile options, ( err, obj ) ->
				obj._remove ids['subprofile'], ( err, obj ) ->
					assert.equal null, err

					done( )

	test 'can remove a profile', ( done ) ->
		waitForId 'profile', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Profile options, ( err, obj ) ->
				obj._remove id, ( err, obj ) ->
					assert.equal null, err

					done( )

	test 'can remove collections', ( done ) ->
		waitForId 'collection', ( id ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Base options, ( err, obj ) ->
				obj.removeCollection id, ( err, obj ) ->
					assert.equal null, err

					done( )

	test 'can use setup exported method', ( done ) ->
		options = copernicaOptions
		copernica.setup options, ( err, results, copernica ) ->
			assert.equal null, err

			ids['deleteallcollections'] = 1

			done( )

	# test 'can use exec exported method', ( done ) ->
	# 	options = copernicaOptions

	# 	done( )

	test 'can remove all collections', ( done ) ->
		waitForId 'deleteallcollections', ( ) ->
			options = copernicaOptions

			new copernica._classes.Copernica_Base options, ( err, obj ) ->
				obj.getCollections ( err, results ) ->
					async.map results, ( ( collection, next ) ->
						obj.removeCollection collection.id, next
					), ( err, results ) ->
						assert.equal null, err

						done( )
