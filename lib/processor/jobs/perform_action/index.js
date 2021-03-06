// Generated by CoffeeScript 1.6.3
(function() {
  var Cache, async;

  async = require('async');

  Cache = require('shared-cache');

  module.exports = function(job, done) {
    var account, accountID, fns, row, time,
      _this = this;
    account = null;
    accountID = job.data.account;
    time = new Date(parseInt(job.created_at));
    row = job.data.data;
    fns = {};
    fns.account = function(next) {
      return loadAccount(accountID, function(err, acc) {
        account = acc;
        return next(err);
      });
    };
    fns.setup = function(next) {
      if (account.actions == null) {
        account.actions = Cache.create('actions-' + accountID, true, function(key, next) {
          return account.database.collection('actions').find().toArray(next);
        });
      }
      return next();
    };
    fns.actions = function(next) {
      return account.actions.get(function(e, r) {
        return next(e, r);
      });
    };
    fns.actionTypes = function(next) {
      return Action_Model.actionTypes(function(e, r) {
        return next(e, r);
      });
    };
    fns.fact = function(next) {
      return new Fact_deferred_Model(account, row.fact_type, function() {
        var model;
        model = this;
        return this.load({
          _id: row.fact_id
        }, true, function(err, fact) {
          var _this = this;
          if (fact == null) {
            fact = {};
          }
          if (err || !fact._id) {
            return next(err || 'Bad ID');
          }
          if (fact._updated.toJSON() !== row.version) {
            return next("Invalid version");
          }
          return this.addShim(function() {
            return next(null, model);
          });
        });
      });
    };
    return async.series(fns, function(err, results) {
      var action, actions, condition, fact, fact_val, filter, iterate, stage, types, value, _base, _ref;
      if (err) {
        console.error(err);
        return done(err);
      }
      filter = function(obj) {
        return row.fact_type === obj.fact_type;
      };
      actions = results.actions.filter(filter);
      fact = results.fact;
      types = results.actionTypes;
      action = actions.filter(filter).filter(function(action) {
        return action.action_id === row.action_id;
      }).pop();
      if (action.length === 0) {
        return done('No such action');
      }
      if ((_base = fact.data)._conditions == null) {
        _base._conditions = {};
      }
      if (row.stage < 0 || (row.stage == null)) {
        _ref = action.conditions;
        for (condition in _ref) {
          value = _ref[condition];
          fact_val = !!fact.data._conditions[condition];
          if (value !== fact_val) {
            return done('Did not match');
          }
        }
      }
      stage = row.stage;
      iterate = function(action, next) {
        var obj, type;
        stage = stage + 1;
        if (!(type = types[action.action])) {
          return next('No such type');
        }
        obj = {
          job: job.data,
          action: action,
          step: action,
          stage: stage,
          fact: fact
        };
        return type.validate(obj, function(err) {
          if (err) {
            return next(err, action);
          }
          return type.exec(obj, next);
        });
      };
      actions = action.actions.slice(row.stage + 1);
      return async.mapSeries(actions, iterate, function(err, result) {
        if (err && err.halt) {
          return done(null, 'Delayed on stage', row.stage + result.length);
        }
        return done(err);
      });
    });
  };

  module.exports.disabled = true;

}).call(this);

/*
//@ sourceMappingURL=index.map
*/
