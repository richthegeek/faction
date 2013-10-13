// Generated by CoffeeScript 1.6.3
var __slice = [].slice;

module.exports = function(stream, config, row) {
  var Account_Model, Cache, Fact_Model, async, lib, models, path, request;
  request = require('request');
  async = require('async');
  Cache = require('shared-cache');
  path = require('path');
  lib = path.resolve(__dirname, '../../../lib');
  models = lib + '/models/';
  Account_Model = require(models + 'account');
  Fact_Model = require(models + 'fact');
  config.models = {
    account: Account_Model
  };
  return function(row, callback) {
    var fns, self,
      _this = this;
    self = this;
    fns = [];
    if (this.accountModel == null) {
      fns.push(function(next) {
        return new Account_Model(function() {
          self.accountModel = this;
          return this.load({
            _id: stream.db.databaseName.replace(/^faction_account_/, '')
          }, next);
        });
      });
    }
    fns.push(function() {
      var account, next;
      next = Array.prototype.pop.call(arguments);
      account = self.accountModel;
      if (self.cache == null) {
        self.cache = Cache.create('hooks-' + account.data._id, true, function(key, next) {
          return stream.db.collection('hooks').find().toArray(next);
        });
      }
      return self.cache.get(function(err, hooks) {
        var hook, _i, _len;
        for (_i = 0, _len = hooks.length; _i < _len; _i++) {
          hook = hooks[_i];
          if (hook.fact_type === row.fact_type && hook.hook_id === row.hook_id) {
            return next(null, account, hook);
          }
        }
        return next('Unknown hook id');
      });
    });
    fns.push(function() {
      var account, hook, next, skip, _i;
      account = arguments[0], hook = arguments[1], skip = 4 <= arguments.length ? __slice.call(arguments, 2, _i = arguments.length - 1) : (_i = 2, []), next = arguments[_i++];
      return new Fact_Model(account, row.fact_type, function() {
        self.table = this.table;
        return this.table.findOne({
          _id: row.data._id
        }, function(err, fact) {
          return next(err, account, hook, fact);
        });
      });
    });
    return async.waterfall(fns, function(err, account, hook, fact) {
      var cb, options;
      if (err) {
        return callback(err);
      }
      if (!fact) {
        return callback();
      }
      if (row.data._updated !== fact._updated) {
        console.log('Expired');
        return next();
      }
      cb = function(err, res, body) {
        return callback(null, {
          hook_id: row.hook_id,
          fact_type: row.fact_type,
          fact_id: fact._id,
          status: res.statusCode,
          body: body,
          time: new Date
        });
      };
      options = {
        method: 'POST',
        uri: hook.url,
        json: row.data
      };
      return request.post(options, cb);
    });
  };
};
