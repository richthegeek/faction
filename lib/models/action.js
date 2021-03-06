// Generated by CoffeeScript 1.6.3
(function() {
  var Action_Model, Cache, Model, async,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  async = require('async');

  Model = require('./model');

  Cache = require('shared-cache');

  module.exports = Action_Model = (function(_super) {
    __extends(Action_Model, _super);

    function Action_Model(account, callback) {
      this.account = account;
      Action_Model.__super__.constructor.call(this, account.dbname(), 'actions', function(self, db, coll) {
        return callback.apply(this, arguments);
      });
    }

    Action_Model.prototype._spawn = function(callback) {
      return new this.constructor(this.account, callback);
    };

    Action_Model.route = function(req, res, next) {
      return new Action_Model(req.account, function() {
        req.model = this;
        return next();
      });
    };

    Action_Model.prototype.validate = function(data, callback) {
      var action, _i, _len, _ref;
      if (!data.conditions) {
        throw 'An action must have a map of conditions determining wether it is run.';
      }
      if (data.perform_once_per_fact == null) {
        data.perform_once_per_fact = false;
      }
      if (!Array.isArray(data.actions) || data.actions.length === 0) {
        throw 'An action must have an array of at least 1 action to perform.';
      }
      _ref = data.actions;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        action = _ref[_i];
        if (!action || !action.action) {
          throw 'All actions must be an object with an "action" property.';
        }
      }
      return this.actionTypes(function(err, types) {
        var iterator;
        iterator = function(action, next) {
          var type;
          if (!(type = types[action.action])) {
            throw "Unknown action '" + action.action + "'. GET /action-types to see a valid list.";
          }
          return type.validate(action, function(err) {
            if (err) {
              return next("Action '" + action.action + "' could not validate: " + err);
            }
            return next();
          });
        };
        return async.each(data.actions, iterator, callback);
      });
    };

    Action_Model.prototype["export"] = function() {
      var data;
      data = Action_Model.__super__["export"].apply(this, arguments);
      return {
        action_id: data.action_id,
        fact_type: data.fact_type,
        actions: data.actions,
        conditions: data.conditions,
        perform_once_per_fact: !!data.perform_once_per_fact
      };
    };

    Action_Model.prototype.fact_is_runnable = function(factObj) {
      var condition, data, fact, val, _ref;
      data = this["export"]();
      fact = factObj["export"]();
      _ref = data.conditions;
      for (condition in _ref) {
        val = _ref[condition];
        if (fact._conditions[condition] !== val) {
          return false;
        }
      }
      return true;
    };

    Action_Model.prototype.fact_run = function(factObj, stage, callback) {
      var _this = this;
      if (typeof stage === 'function') {
        callback = stage;
        stage = 0;
      }
      if (typeof Number(stage) !== 'number') {
        stage = 0;
      }
      if (stage === 0) {
        if (!this.fact_is_runnable(factObj)) {
          return callback(null, false);
        }
      }
      return this.actionTypes(function(err, types) {
        var index, runner;
        index = stage;
        runner = function(action, next) {
          var info, type;
          if (type = types[action.action]) {
            info = {
              step: action,
              action: _this["export"](),
              fact: factObj["export"](),
              fact_type: factObj.type,
              account: _this.account,
              stage: index++
            };
            return type.exec(info, function(err, res, broke) {
              if (broke == null) {
                broke = false;
              }
              if (err) {
                return next('err', err);
              } else if (broke) {
                return next('break', res);
              } else {
                return next(null, res);
              }
            });
          }
        };
        return async.mapSeries(_this.data.actions.slice(stage), runner, function(e, r) {
          if (e === 'err') {
            e = r;
            r = null;
          }
          if (e === 'break') {
            e = null;
          }
          return callback(e, r, index - 1);
        });
      });
    };

    Action_Model.actionTypes = Action_Model.prototype.actionTypes = function(callback) {
      var cache,
        _this = this;
      cache = Cache.create('action-types', true, function(key, next) {
        var dir, file, fs, name, object, path, types, _i, _len, _ref;
        fs = require('fs');
        path = require('path');
        dir = path.resolve(__dirname, '../actions');
        types = {};
        _ref = fs.readdirSync(dir);
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          file = _ref[_i];
          if (!(file.substr(-3) === '.js')) {
            continue;
          }
          name = file.slice(0, -3);
          object = require(dir + '/' + file);
          types[object.name] = object;
        }
        return next(null, types);
      });
      return cache.get(callback);
    };

    Action_Model.prototype.setup = function() {
      var path;
      path = require('path');
      return this.db.addStreamOperation({
        _id: 'action_eval',
        sourceCollection: 'fact_evaluated',
        targetCollection: 'action_results',
        type: 'untracked',
        operations: [
          {
            modular: true,
            operation: path.resolve(__dirname, '../../opstreams/perform_action')
          }
        ]
      });
    };

    return Action_Model;

  })(Model);

}).call(this);

/*
//@ sourceMappingURL=action.map
*/
