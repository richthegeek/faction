fs = require 'fs'

{print} = require 'sys'
{spawn} = require 'child_process'

build = ( callback, windows = false ) ->
	bin = 'coffee'
	if windows or process.platform is 'win32'
		bin += '.cmd'
	coffee = spawn bin, ['-c', '-o', 'lib', 'src']
	coffee.stderr.on 'data', ( data ) ->
		process.stderr.write data.toString( )
	coffee.stdout.on 'data', ( data ) ->
		print data.toString( )
	coffee.on 'exit', ( code ) ->
		callback?( ) if code is 0

task 'build', 'Build lib/ from src/ [LINUX]', ->
	build( )

task 'wbuild', 'Build lib/ from src/ [WINDOWS]', ->
	build null, true

task 'sbuild', 'Build lib/ from src/ [SUBLIME]', ->
	build( )
