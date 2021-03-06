// Generated by CoffeeScript 1.6.3
(function() {
  var Cache;

  Cache = require('shared-cache');

  module.exports = function(server) {
    return server.post('/info/:info-type', Info_Model.route, function(req, res, next) {
      var mappings, _ref, _ref1;
      mappings = Cache.create('info-mappings-' + req.account.data._id, true, function(key, next) {
        return new Infomapping_Model(req.account, function() {
          return this.table.find().toArray(next);
        });
      });
      res.logMessage = req.params['info-type'];
      if (((_ref = req.body) != null ? (_ref1 = _ref.action) != null ? _ref1.type : void 0 : void 0) != null) {
        res.logMessage += '/' + req.body.action.type;
      }
      req.logTime('precreate');
      return req.model.create(req.params['info-type'], req.body, req.logTime, function(err) {
        req.logTime('procreate');
        if (err) {
          return next(err);
        }
        return mappings.get(ErrorHandler(next, function(err, list, hit) {
          var mapping;
          res.send({
            status: 'ok',
            statusText: 'Information recieved',
            mappings: (function() {
              var _i, _len, _results;
              _results = [];
              for (_i = 0, _len = list.length; _i < _len; _i++) {
                mapping = list[_i];
                if (mapping.info_type === req.params['info-type']) {
                  _results.push(Infomapping_Model["export"](mapping));
                }
              }
              return _results;
            })()
          });
          return next();
        }));
      });
    });
  };

}).call(this);

/*
//@ sourceMappingURL=info.map
*/
