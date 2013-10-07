// Generated by CoffeeScript 1.6.3
module.exports = function(stream, config, row) {
  var evaluate, interpolate, parseObject;
  evaluate = function(str, context, callback) {
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

  interpolate = function(str, context, callback) {
    var _this = this;
    (str.match(/\#\{.+?\}/g) || []).forEach(function(section) {
      return str = str.replace(section, evaluate(section.slice(2, -1), context));
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

  parseObject = function(obj, context, callback) {
    var iter, nodes, traverse,
      _this = this;
    obj = JSON.parse(JSON.stringify(obj), function(key, value) {
      var k, v;
      if (Object.prototype.toString.call(value) === '[object Object]') {
        for (k in value) {
          v = value[k];
          delete value[k];
          k = interpolate(k, context);
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
    iter = function(node, next) {
      return evaluate(node.value, context, function(err, newval) {
        return next(err, node.update(newval, true));
      });
    };
    return async.each(nodes, iter, function() {
      return callback(obj);
    });
  };
  return {
    evaluate: evaluate,
    interpolate: interpolate,
    parseObject: parseObject
  };
};
