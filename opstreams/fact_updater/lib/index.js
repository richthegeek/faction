// Generated by CoffeeScript 1.6.3
var __slice = [].slice;

module.exports = function(stream, config) {
  var Account_Model, Cache, Fact_Model, account_name, async, lib, models, path, s, t, _hooks, _settings;
  async = require('async');
  Cache = require('shared-cache');
  path = require('path');
  lib = path.resolve(__dirname, '../../../lib');
  models = lib + '/models/';
  Account_Model = require(models + 'account');
  Fact_Model = require(models + 'fact_deferred');
  config.models = {
    account: Account_Model,
    fact: Fact_Model
  };
  account_name = stream.db.databaseName.replace(/^faction_account_/, '');
  _settings = Cache.create('fact-settings-' + account_name, true, function(key, next) {
    return stream.db.collection('fact_settings').find().toArray(next);
  });
  _hooks = Cache.create('hooks-' + account_name, true, function(key, next) {
    return stream.db.collection('hooks').find().toArray(next);
  });
  s = +(new Date);
  t = function() {
    var args;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    args.push((+(new Date)) - s);
    return console.log.apply(console.log, args);
  };
  return function(row, callback) {
    var fns, self,
      _this = this;
    self = this;
    fns = {};
    if (this.accountModel == null) {
      fns.account = function(next) {
        return new Account_Model(function() {
          self.accountModel = this;
          return this.load({
            _id: account_name
          }, next);
        });
      };
    }
    fns.hooks = function(next) {
      return _hooks.get(next);
    };
    fns.settings = function(next) {
      return _settings.get(next);
    };
    return async.series(fns, function(err, results) {
      var hooks, settings;
      hooks = results.hooks[0].filter(function(hook) {
        return hook.fact_type === row.type;
      });
      settings = results.settings[0].filter(function(setting) {
        return setting._id === row.type;
      }).pop();
      return new Fact_Model(_this.accountModel, row.type, function() {
        var model;
        model = this;
        return this.load({
          _id: row.id
        }, true, function(err, fact) {
          var _this = this;
          if (fact == null) {
            fact = {};
          }
          if (err || !fact._id) {
            return callback(err, null);
          }
          return this.addShim(function() {
            var evals, evaluate, key, props;
            evals = (function() {
              var _ref, _results;
              _ref = settings.field_modes;
              _results = [];
              for (key in _ref) {
                props = _ref[key];
                if (props["eval"]) {
                  _results.push([key, props]);
                }
              }
              return _results;
            })();
            evaluate = function(arr, next) {
              key = arr[0], props = arr[1];
              return _this.withMap([], props.map, false, function(err, map) {
                return _this.data["eval"](props["eval"], map, function(err, result) {
                  var _ref;
                  result = (_ref = result != null ? result : props["default"]) != null ? _ref : null;
                  console.log(props["eval"], map, result);
                  return next(null, {
                    key: key,
                    value: result
                  });
                });
              });
            };
            return async.mapSeries(evals, evaluate, function(err, columns) {
              var cb;
              fact = JSON.parse(JSON.stringify(_this));
              cb = function(next) {
                return next();
              };
              if (columns.length > 0) {
                cb = function(next) {
                  columns.forEach(function(column) {
                    return _this.data.set.call(fact, column.key, column.value);
                  });
                  for (key in settings.foreign_keys) {
                    _this.data.del.call(fact, key);
                  }
                  return _this.table.save(fact, next);
                };
              }
              return cb(function(err) {
                var data;
                data = hooks.map(function(hook) {
                  var ret;
                  ret = {
                    hook_id: hook.hook_id,
                    fact_type: hook.fact_type,
                    fact_id: fact._id
                  };
                  if (hook.mode !== 'snapshot') {
                    ret.fact_id = (Math.round(999 * Math.random())) + (+(new Date));
                    ret.data = fact;
                  }
                  return ret;
                });
                data = data.filter(Boolean);
                if (data.length > 0) {
                  stream.db.collection('hooks_pending').insert(data, function(err) {
                    if (err) {
                      if (err.code === 11000) {
                        return;
                      }
                      console.error('Add hook error', arguments);
                      throw err;
                    }
                  });
                }
                return callback(null, {
                  id: row.id,
                  type: row.type,
                  updated_fields: (function() {
                    var _ref, _results;
                    _ref = settings.field_modes;
                    _results = [];
                    for (key in _ref) {
                      props = _ref[key];
                      if (props["eval"]) {
                        _results.push(key);
                      }
                    }
                    return _results;
                  })(),
                  hooks: hooks.map(function(hook) {
                    return hook.hook_id;
                  }),
                  fact: fact
                });
              });
            });
          });
        });
      });
    });
  };
};

/*
//@ sourceMappingURL=index.map
*/
