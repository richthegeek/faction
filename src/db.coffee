mongodb = require 'mongodb-opstream'

global.config = config or {}
config.db ?= {}
config.db?.host ?= 'localhost'
config.db?.port ?= 27017


module.exports = mongodb
