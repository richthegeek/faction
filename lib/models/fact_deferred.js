// Generated by CoffeeScript 1.6.3
(function() {
  var Cache, DeferredObject, Fact_deferred_Model, Model, async, moment, wrapArray,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  async = require('async');

  Model = require('./model');

  Cache = require('shared-cache');

  DeferredObject = require('deferred-object');

  wrapArray = require('../lib/wrapArray');

  module.exports = Fact_deferred_Model = (function(_super) {
    __extends(Fact_deferred_Model, _super);

    function Fact_deferred_Model(account, type, callback) {
      this.account = account;
      this.type = type;
      this.type = type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60);
      Fact_deferred_Model.__super__.constructor.call(this, account.dbname(), this.collectionname(), function(self, db, coll) {
        return callback.apply(this, arguments);
      });
    }

    Fact_deferred_Model.prototype._spawn = function(callback) {
      return new this.constructor(this.account, this.type, callback);
    };

    Fact_deferred_Model.collectionname = Fact_deferred_Model.prototype.collectionname = function(type) {
      if (type == null) {
        type = this.type;
      }
      return 'facts_' + type.replace(/[^a-z0-9_]+/g, '_').substring(0, 60);
    };

    Fact_deferred_Model.route = function(req, res, next) {
      if (req.params['fact-type']) {
        return new Fact_deferred_Model(req.account, req.params['fact-type'], function() {
          req.model = this;
          return next();
        });
      } else {
        return next();
      }
    };

    Fact_deferred_Model.prototype.removeFull = function(callback) {
      return this.table.drop(callback);
    };

    Fact_deferred_Model.markUpdated = function(id, type, account, callback) {
      return jobs.create('fact_update', {
        title: "" + type + " - " + id,
        account: account._id || account,
        data: {
          fact_id: id,
          fact_type: type,
          version: null
        }
      }).save(function(err) {
        return callback(err, id);
      });
    };

    Fact_deferred_Model.prototype.markUpdated = function(callback) {
      if (this.data._id) {
        return Fact_deferred_Model.markUpdated(this.data._id, this.type, this.account.data._id, callback);
      } else {
        return callback();
      }
    };

    Fact_deferred_Model.prototype.markUpdatedFull = function(query, callback) {
      var _this = this;
      if (typeof query === 'function') {
        callback = query;
        query = {};
      }
      return this.table.find(query).count(function(err, count) {
        return jobs.create('fact_update_all', {
          title: _this.type,
          account: _this.account.data._id,
          data: {
            query: query,
            fact_type: _this.type,
            version: null
          }
        }).save(function(err2) {
          return callback(err || err2, count);
        });
      });
    };

    Fact_deferred_Model.prototype["export"] = function() {
      if (this.data.data) {
        return this.data.data;
      }
      return this.data;
    };

    Fact_deferred_Model.prototype["import"] = function(data, defer, callback) {
      var args, _ref,
        _this = this;
      args = Array.prototype.slice.call(arguments, 1);
      callback = args.pop();
      defer = (_ref = args.pop()) != null ? _ref : true;
      return this.getSettings(function(err, settings) {
        var key, val;
        _this.data = {};
        if (settings.foreign_keys == null) {
          settings.foreign_keys = {};
        }
        for (key in data) {
          val = data[key];
          if (settings.foreign_keys[key] == null) {
            _this.data[key] = val;
          }
        }
        if (defer) {
          return _this.defer(function() {
            return callback(err, _this.data);
          });
        } else {
          return callback(err, _this.data);
        }
      });
    };

    Fact_deferred_Model.prototype.defer = function(callback) {
      var self,
        _this = this;
      self = this;
      this.data = new DeferredObject(this.data || {});
      return this.getSettings(function(err, settings) {
        var key, props, _ref;
        _ref = settings.foreign_keys || {};
        for (key in _ref) {
          props = _ref[key];
          delete _this.data[key];
          _this.data.defer(key, function(key, data, next) {
            props = settings.foreign_keys[key];
            return Fact_deferred_Model.parseObject(props.query, {
              fact: self.data
            }, function(err, query) {
              if (err) {
                return next(err);
              }
              return new Fact_deferred_Model(self.account, props.fact_type, function() {
                if (props.has === 'one' || (query._id != null)) {
                  return this.load(query, next);
                } else {
                  return this.loadAll(query, next);
                }
              });
            });
          });
        }
        return callback.call(_this, _this.data);
      });
    };

    Fact_deferred_Model.prototype.load = function(query, defer, callback) {
      var args, _ref, _ref1,
        _this = this;
      args = Array.prototype.slice.call(arguments, 1);
      callback = args.pop();
      defer = (_ref = args.pop()) != null ? _ref : true;
      if ((query instanceof mongodb.ObjectID) || ((_ref1 = typeof query) === 'string' || _ref1 === 'number')) {
        query = {
          _id: query
        };
      }
      return this.table.findOne(query, function(err, row) {
        if (err || !row) {
          return callback(err, row);
        }
        return _this["import"](row, defer, function() {
          return callback.call(_this, err, _this.data, query);
        });
      });
    };

    Fact_deferred_Model.prototype.loadAll = function(query, defer, callback) {
      var args, _ref,
        _this = this;
      args = Array.prototype.slice.call(arguments, 1);
      callback = args.pop();
      defer = (_ref = args.pop()) != null ? _ref : true;
      return this.table.find(query, {
        _id: 1
      }).toArray(function(err, ids) {
        var loader;
        loader = function(row, next) {
          return _this._spawn(function() {
            return this.load({
              _id: row._id
            }, defer, next);
          });
        };
        return async.map(ids, loader, function(err, rows) {
          return callback.call(this, err, wrapArray(rows));
        });
      });
    };

    Fact_deferred_Model.prototype.loadPaginated = function(conditions, req, callback) {
      return Fact_deferred_Model.__super__.loadPaginated.call(this, conditions, req, function(err, response) {
        var loader;
        if (err) {
          return callback(err, response);
        }
        loader = function(item, next) {
          return item.withMap(req.body["with"], req.body.map, next);
        };
        return async.map(response.items, loader, function(err, items) {
          response.items = items;
          return callback(err, response);
        });
      });
    };

    Fact_deferred_Model.prototype.addShim = function(callback) {
      var addShim, file;
      file = require('path').resolve(__dirname, '../processor/jobs/info/add_shim');
      addShim = require(file);
      return addShim(this.data, callback);
    };

    Fact_deferred_Model.prototype.updateFields = function(callback) {
      var _this = this;
      return this.addShim(function(err, fact) {
        return _this.getSettings(function(err, settings) {
          var key, props, result, _ref;
          _ref = settings.field_modes;
          for (key in _ref) {
            props = _ref[key];
            if (!props["eval"]) {
              continue;
            }
            result = Fact_deferred_Model.evaluate(props["eval"], {
              fact: fact
            });
            fact.set(key, result);
          }
          _this.data = fact;
          return callback.call(_this, err, fact);
        });
      });
    };

    Fact_deferred_Model.prototype.evaluateCondition = function(condition, context, callback) {
      var args, evalCond, fact;
      args = Array.prototype.slice.call(arguments);
      callback = args.pop() || function() {
        return null;
      };
      context = args.pop() || {};
      fact = this;
      evalCond = function(cond, next2) {
        return fact.data["eval"](cond, context, function(err, result) {
          return next2(err, Boolean(result));
        });
      };
      condition = condition.data || condition;
      return async.mapSeries(condition.conditions, evalCond, callback);
    };

    Fact_deferred_Model.prototype.withMap = function(_with, map, context, shim, callback) {
      var args, get,
        _this = this;
      args = Array.prototype.slice.call(arguments, 2);
      callback = args.pop();
      shim = args.pop() || true;
      if (typeof shim !== 'boolean') {
        context = shim;
        shim = true;
      } else {
        context = args.pop() || {};
      }
      _with = [].concat.call([], _with != null ? _with : []);
      map = map || {};
      get = function(part, next) {
        var start;
        start = +(new Date);
        part = "this." + part.replace(/^(this|fact)\./, '');
        return _this.data["eval"](part, context, function(err, result) {
          return next(err, result);
        });
      };
      return async.map(_with, get, function() {
        if (!map) {
          return res.send(_this.data);
        }
        return _this.addShim(function() {
          var key, maps, obj, path;
          obj = {};
          get = function(arg, next) {
            var def, key, path;
            key = arg[0], path = arg[1];
            def = null;
            if (Array.isArray(path)) {
              def = path[1];
              path = path[0];
            }
            return _this.data["eval"](path, context, function(err, result) {
              if (err) {
                console.log('WM', _this.data.data._id, path, err);
              }
              return next(null, obj[key] = context[key] = result || def);
            });
          };
          maps = (function() {
            var _results;
            _results = [];
            for (key in map) {
              path = map[key];
              _results.push([key, path]);
            }
            return _results;
          })();
          if (maps.length > 0) {
            maps.unshift(['_id', 'this._id']);
            return async.mapSeries(maps, get, function() {
              return callback(null, obj);
            });
          } else {
            return callback(null, _this.data);
          }
        });
      });
    };

    Fact_deferred_Model.prototype.getSettings = function(callback) {
      var _this = this;
      if (this.settings_cache == null) {
        this.settings_cache = Cache.create('fact-settings-' + this.account.data._id, true, function(key, next) {
          return _this.db.collection('fact_settings').find().toArray(next);
        });
      }
      return this.settings_cache.get(function(err, settings) {
        return callback(err, settings.filter(function(setting) {
          return setting._id === _this.type;
        }).pop() || {});
      });
    };

    Fact_deferred_Model.getTypes = function(account, callback) {
      return mongodb.open(account.dbname(), function(err, db) {
        return db.collectionNames(function(err, cl) {
          var collections, filter, rename, result, trim;
          collections = cl;
          rename = function(row) {
            return row.name.split('.').pop();
          };
          filter = function(name) {
            return name.slice(0, 6) === 'facts_';
          };
          trim = function(name) {
            return name.slice(6);
          };
          result = cl.map(rename).filter(filter).map(trim);
          result.detailed = function(callback) {
            var iter;
            iter = function(type, next) {
              return new Fact_deferred_Model(account, type, function() {
                return this.table.count(function(err, size) {
                  return next(err, {
                    fact_type: type,
                    fact_sources: 'todo',
                    count: size,
                    nextPage: "/facts/" + type
                  });
                });
              });
            };
            return async.map(result, iter, function(err, info) {
              var fact, obj, _i, _len, _ref;
              obj = {};
              _ref = info || [];
              for (_i = 0, _len = _ref.length; _i < _len; _i++) {
                fact = _ref[_i];
                obj[fact.fact_type] = fact;
              }
              return callback(err, obj);
            });
          };
          return callback(err, result);
        });
      });
    };

    return Fact_deferred_Model;

  })(Model);

  moment = require('moment');

  Fact_deferred_Model.evaluate = function(str, context, callback) {
    var fn;
    context.isAsync = false;
    context.async = function(val) {
      if (val == null) {
        val = true;
      }
      return context.isAsync = val;
    };
    context.complete = function(err, str) {
      context.complete = function() {
        return null;
      };
      return process.nextTick(function() {
        return typeof callback === "function" ? callback(err, str) : void 0;
      });
    };
    context.moment = moment;
    fn = function() {
      var e;
      try {
        with(context) { str = eval(str) };
      } catch (_error) {
        e = _error;
        return context.complete(e, str);
      }
      if (!context.isAsync) {
        context.complete(null, str);
        return str;
      }
      return null;
    };
    return fn.bind({})();
  };

  /*
  interpolate: evaluate demarcated sections of a string
  */


  Fact_deferred_Model.interpolate = function(str, context, callback) {
    var _this = this;
    (str.match(/\#\{.+?\}/g) || []).forEach(function(section) {
      return str = str.replace(section, Fact_deferred_Model.evaluate(section.slice(2, -1), context));
    });
    return str;
  };

  /*
  parseObject: evaluate the object with this context, interpolating keys and evaluating leaves.
  	Should transform an object like:
  		"orders": "item", "order_#{item.oid}_value": "item.value"
  	Into this:
  		"orders": {oid: 42, value: 400}, "orders_42_value": 400
  */


  Fact_deferred_Model.parseObject = function(obj, context, callback) {
    var errors, iter, nodes, traverse,
      _this = this;
    obj = JSON.parse(JSON.stringify(obj), function(key, value) {
      var k, v;
      if (Object.prototype.toString.call(value) === '[object Object]') {
        for (k in value) {
          v = value[k];
          delete value[k];
          k = Fact_deferred_Model.interpolate(k, context);
          value[k] = v;
        }
      }
      return value;
    });
    nodes = [];
    traverse = require('traverse');
    traverse(obj).forEach(function(val) {
      if (this.isLeaf) {
        this.value = val;
        return nodes.push(this);
      }
    });
    errors = [];
    iter = function(node, next) {
      return Fact_deferred_Model.evaluate(node.value, context, function(err, newval) {
        if (err) {
          errors.push(err);
        } else {
          node.update(newval, true);
        }
        return next();
      });
    };
    return async.each(nodes, iter, function() {
      var err;
      err = (errors.length ? errors : null);
      return callback(err, obj);
    });
  };

}).call(this);

/*
//@ sourceMappingURL=fact_deferred.map
*/
