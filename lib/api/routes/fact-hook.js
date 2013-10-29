// Generated by CoffeeScript 1.6.3
(function() {
  module.exports = function(server) {
    server.get('/facts/:fact-type/hooks', Hook_Model.route, function(req, res, next) {
      console.log(req.params.asQuery());
      return req.model.loadPaginated(req.params.asQuery(), req, ErrorHandler(next, function(err, response) {
        return res.send(response);
      }));
    });
    server.post('/facts/:fact-type/hooks/:hook-id', Hook_Model.route, function(req, res, next) {
      var _this = this;
      delete req.body._id;
      req.body.fact_type = req.params['fact-type'];
      req.body.hook_id = req.params['hook-id'];
      return req.model.update(req.params.asQuery(), req.body, ErrorHandler(next, function(err, updated) {
        return res.send({
          status: 'ok',
          statusText: 'The hook was ' + (updated && 'updated.' || 'created.'),
          hook: req.model["export"]()
        });
      }));
    });
    return server.del('/facts/:fact-type/hooks/:hook-id', Hook_Model.route, function(req, res, next) {
      return req.model.remove(req.params.asQuery(), function(err, count) {
        return res.send({
          status: 'ok',
          statusText: 'The hook was deleted.',
          deleted: count | 0
        });
      });
    });
  };

}).call(this);

/*
//@ sourceMappingURL=fact-hook.map
*/