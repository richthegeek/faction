// Generated by CoffeeScript 1.6.3
var __slice = [].slice;

module.exports = function(stream, config) {
  var Account_Model, Cache, Fact_Model, InfoMapping_Model, account_name, async, lib, models, path, _hooks, _mappings, _settings;
  async = require('async');
  Cache = require('shared-cache');
  path = require('path');
  lib = path.resolve(__dirname, '../../../lib');
  models = lib + '/models/';
  Account_Model = require(models + 'account');
  InfoMapping_Model = require(models + 'infomapping');
  Fact_Model = require(models + 'fact');
  config.models = {
    account: Account_Model,
    infomapping: InfoMapping_Model,
    fact: Fact_Model
  };
  account_name = stream.db.databaseName.replace(/^faction_account_/, '');
  _mappings = Cache.create('info-mappings-' + account_name, true, function(key, next) {
    return stream.db.collection('info_mappings').find().toArray(next);
  });
  _settings = Cache.create('fact-settings-' + account_name, true, function(key, next) {
    return stream.db.collection('fact_settings').find().toArray(next);
  });
  _hooks = Cache.create('hooks-' + account_name, true, function(key, next) {
    return stream.db.collection('hooks').find().toArray(next);
  });
  return function(row, callback) {
    var addShim, evaluate, fns, markForeignFacts, mergeFacts, parseObject, self, _ref,
      _this = this;
    self = this;
    config.time = row._id.getTimestamp() || new Date;
    mergeFacts = require('./merge_facts')(stream, config, row);
    markForeignFacts = require('./mark_foreign_facts')(stream, config, row);
    addShim = require('./add_shim')(stream, config, row);
    _ref = require('./eval')(stream, config, row), evaluate = _ref.evaluate, parseObject = _ref.parseObject;
    fns = [];
    if (this.accountModel == null) {
      fns.push(function(next) {
        return new Account_Model(function() {
          self.accountModel = this;
          return this.load({
            _id: account_name
          }, next);
        });
      });
    }
    /*
    		A sample mapping:
    			info_type: 'visit',
    			fact_type: 'sessions',
    			fact_identifier: 'info.sid',
    			fields:
    				uid: 'info.uid'
    				visits:
    					url: 'info.url',
    					time: 'new Date'
    
    		A sample fact setting:
    			fact_type: 'sessions'
    			field_modes:
    				actions: 'all'
    				score:
    					eval: "
    						async();
    						http.request("http://trakapo.com/score", {})
    
    					"
    			foreign_keys:
    				user:
    					fact_type: 'users'
    					has: 'one'
    					query:
    						_id: 'fact.uid'
    
    		With this we need to:
    		 - find the fact_identifier in the facts_sessions collection
    		 - load the fact settings for the "sessions" fact (cache!)
    		 - merge the new info into the existing fact
    		 - save, ping any FKs as updated.
    */

    fns.push(function() {
      var account, next, skip, _i;
      account = arguments[0], skip = 3 <= arguments.length ? __slice.call(arguments, 1, _i = arguments.length - 1) : (_i = 1, []), next = arguments[_i++];
      return _mappings.get(function(err, mappings) {
        return next(err, mappings);
      });
    });
    fns.push(function() {
      var mappings, next, skip, _i;
      mappings = arguments[0], skip = 3 <= arguments.length ? __slice.call(arguments, 1, _i = arguments.length - 1) : (_i = 1, []), next = arguments[_i++];
      return _settings.get(function(err, settings) {
        return next(err, mappings, settings);
      });
    });
    fns.push(function() {
      var mappings, next, settings, skip, _i;
      mappings = arguments[0], settings = arguments[1], skip = 4 <= arguments.length ? __slice.call(arguments, 2, _i = arguments.length - 1) : (_i = 2, []), next = arguments[_i++];
      return _hooks.get(function(err, hooks) {
        return next(err, mappings, settings, hooks);
      });
    });
    return async.waterfall(fns, function(err, mappings, settings, hooks) {
      var account, combineMappings, parseMappings;
      account = _this.accountModel;
      parseMappings = function(mapping, next) {
        var query;
        if (mapping.info_type !== row._type) {
          return next();
        }
        query = {
          _id: evaluate(mapping.fact_identifier, {
            info: row
          })
        };
        return new Fact_Model(account, mapping.fact_type, function() {
          var model;
          model = this;
          return this.load(query, true, function(err, fact) {
            if (fact == null) {
              fact = {};
            }
            if (err) {
              return next(err);
            }
            return addShim(fact, account, this.db, this.table, this.type, function(err, fact) {
              delete row._type;
              if (Object.prototype.toString.call(row._id) === '[object Object]') {
                delete row._id;
              }
              return parseObject(mapping.fields, {
                info: row,
                fact: fact
              }, function(obj) {
                obj._id = query._id;
                return next(null, {
                  model: model,
                  fact: fact,
                  mapping: mapping,
                  info: obj
                });
              });
            });
          });
        });
      };
      combineMappings = function(info, next) {
        var set;
        set = info.fact.getSettings();
        return info.model["import"](mergeFacts(set, info.fact, info.info), function() {
          return addShim(this.data, account, this.db, this.table, this.type, function(err, fact) {
            var data, key, mode, modes, props;
            modes = set.field_modes;
            for (key in modes) {
              props = modes[key];
              if (props["eval"]) {
                fact[key] = evaluate(props["eval"], {
                  fact: fact
                });
              }
            }
            for (key in modes) {
              mode = modes[key];
              if (mode === 'delete') {
                delete fact[key];
              }
            }
            fact._updated = new Date;
            data = hooks.map(function(hook) {
              if (hook.fact_type !== row._type) {
                return null;
              }
              return {
                hook_id: hook.hook_id,
                fact_type: hook.fact_type,
                data: fact
              };
            });
            data = data.filter(function(v) {
              return v != null;
            });
            stream.db.collection('hooks_pending').insert(data, function() {
              return console.log('Hooks', arguments);
            });
            for (key in set.foreign_keys) {
              delete fact[key];
            }
            return info.model.table.save(fact, function(err) {
              var field, fk, iter_wrap, list;
              list = (function() {
                var _ref1, _results;
                _ref1 = set.foreign_keys || {};
                _results = [];
                for (field in _ref1) {
                  fk = _ref1[field];
                  _results.push(fk);
                }
                return _results;
              })();
              iter_wrap = function(fk, next) {
                return markForeignFacts(fk, fact, next);
              };
              return async.map(list, iter_wrap, function(err, updates) {
                updates = updates.filter(function(v) {
                  return v && v.length > 0;
                });
                updates.push({
                  id: fact._id,
                  type: info.mapping.fact_type,
                  time: +(new Date)
                });
                return next(err, updates);
              });
            });
          });
        });
      };
      return async.map(mappings, parseMappings, function(err, result) {
        result = [].concat.apply([], result).filter(function(r) {
          return !!r;
        });
        return async.map(result, combineMappings, function(err, result) {
          result = [].concat.apply([], result);
          result = [].concat.apply([], result);
          result = result.filter(function(r) {
            return (!!r) && !Array.isArray(r);
          });
          return callback(err, result);
        });
      });
    });
  };
};
