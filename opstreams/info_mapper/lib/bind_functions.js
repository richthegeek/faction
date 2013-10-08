// Generated by CoffeeScript 1.6.3
var __hasProp = {}.hasOwnProperty,
  __slice = [].slice;

module.exports = function(stream, config, row) {
  return function(data) {
    var bind_array, bind_iterable, moment, traverse;
    moment = require('moment');
    traverse = require('traverse');
    bind_array = function(value) {
      var compare, item;
      if (((function() {
        var _i, _len, _results;
        _results = [];
        for (_i = 0, _len = value.length; _i < _len; _i++) {
          item = value[_i];
          if ((item._value != null) && (item._date != null)) {
            _results.push(1);
          }
        }
        return _results;
      })()).length > 0) {
        value.over = function(period, time) {
          var bits, duration, end, seconds, start;
          end = Number(time) || new Date().getTime();
          if (bits = period.match(/^([0-9]+) (second|minute|hour|day|week|month|year)/)) {
            duration = moment.duration(Number(bits[1]), bits[2]);
            start = end - duration;
            if (0 === duration.as('milliseconds')) {
              throw 'Invocation of Array.over with invalid duration string.';
            }
          } else if (seconds = Number(period)) {
            start = end - seconds;
          } else {
            throw 'Invocation of Array.over with invalid duration value.';
          }
          return this.betweenDates(start, end);
        };
        value.before = function(time) {
          return this.betweenDates(0, time);
        };
        value.after = function(time) {
          return this.betweenDates(time, new Date);
        };
        value.betweenDates = function(start, end) {
          return bind_array(this.filter(function(item) {
            var _ref;
            return (new Date(start) <= (_ref = new Date(item._date || new Date())) && _ref <= new Date(end));
          }));
        };
      }
      value.values = function(column) {
        return bind_array(this.filter(function(v) {
          return typeof v !== 'function';
        }).map(function(v) {
          var _ref;
          v = (_ref = v._value) != null ? _ref : v;
          return column && v[column] || v;
        }));
      };
      value.sum = function(column) {
        return this.values(column).reduce((function(pv, cv) {
          return pv + (cv | 0);
        }), 0);
      };
      value.max = function(column) {
        return this.values(column).reduce((function(pv, item) {
          return Math.max(pv, item | 0);
        }), Math.max());
      };
      value.min = function(column) {
        return this.values(column).reduce((function(pv, item) {
          return Math.min(pv, item | 0);
        }), Math.min());
      };
      value.mean = function(column) {
        return this.sum(column) / this.values(column).length;
      };
      compare = function(column, val, fn) {
        var args;
        args = Array.prototype.slice.call(arguments);
        fn = args.pop();
        val = args.pop();
        column = args.pop();
        return this.values(column).filter(function(v) {
          return fn(val, v);
        });
      };
      value.gt = function(column, val) {
        return compare.call(this, column, val, function(val, v) {
          return v > val;
        });
      };
      value.gte = function(column, val) {
        return compare.call(this, column, val, function(val, v) {
          return v >= val;
        });
      };
      value.lt = function(column, val) {
        return compare.call(this, column, val, function(val, v) {
          return v < val;
        });
      };
      value.lte = function(column, val) {
        return compare.call(this, column, val, function(val, v) {
          return v <= val;
        });
      };
      value.match = function(params) {
        var args, v;
        args = Array.prototype.slice.call(arguments);
        if (args.length > 1 && typeof args[0] === 'string') {
          params = {};
          while (args.length >= 2) {
            params[args.shift()] = args.shift();
          }
        }
        v = this.values().filter(function(row) {
          var e, key, r, reg, test, val;
          for (key in params) {
            if (!__hasProp.call(params, key)) continue;
            val = params[key];
            test = function(row_val) {
              return val === row_val;
            };
            if (!val) {
              test = function(row_val) {
                return !row_val;
              };
            }
            if (typeof val === 'string' && (r = val.match(/^\/(.+)\/$/))) {
              try {
                reg = new RegExp(r[1]);
                test = function(row_val) {
                  return reg.test(val);
                };
              } catch (_error) {
                e = _error;
                return false;
              }
            }
            if (!test(row[key])) {
              return false;
            }
          }
          return true;
        });
        return v;
      };
      return value;
    };
    bind_iterable = function(value) {
      return value.path = function() {
        var args, gc, op, r;
        args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
        op = stream.operations[0];
        gc = op.getColumn;
        args.unshift(this);
        r = gc.apply(op, args);
        if (Array.isArray(r)) {
          r = bind_array(r);
        }
        return r;
      };
    };
    traverse(data).forEach(function(value) {
      var type;
      type = Object.prototype.toString.call(value).slice(8, -1);
      if (type === 'Array') {
        value = bind_array(value);
      }
      if (type === 'Object' || type === 'Array') {
        value = bind_iterable(value);
      }
      return this.update(value);
    });
    return data;
  };
};
