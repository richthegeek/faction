// Generated by CoffeeScript 1.6.3
var Q, init, request;

Q = require('q');

request = require('request');

init = request.Request.prototype.init;

request.Request.prototype.init = function(options) {
  var defer, key, val, _ref;
  defer = Q.defer();
  this.on('complete', function(req) {
    return defer.resolve(req.body);
  });
  this.on('error', defer.reject);
  if (this.callback == null) {
    this.callback = function() {
      return null;
    };
  }
  _ref = defer.promise;
  for (key in _ref) {
    val = _ref[key];
    if (key !== 'timeout') {
      if (this[key] == null) {
        this[key] = defer.promise[key];
      }
    }
  }
  return init.call(this, options);
};

module.exports = request;

/*
//@ sourceMappingURL=http.map
*/