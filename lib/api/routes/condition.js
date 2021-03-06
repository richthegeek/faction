// Generated by CoffeeScript 1.6.3
(function() {
  module.exports = function(server) {
    var evaluate;
    server.get('/conditions', Condition_Model.route, function(req, res, next) {
      return req.model.loadPaginated({}, req, ErrorHandler(next, function(err, response) {
        return res.send(response);
      }));
    });
    server.get('/conditions/:fact-type', Condition_Model.route, function(req, res, next) {
      return req.model.loadPaginated(req.params.asQuery(), req, ErrorHandler(next, function(err, response) {
        return res.send(response);
      }));
    });
    server.get('/conditions/:fact-type/:condition-id', Condition_Model.route, function(req, res, next) {
      return req.model.load(req.params.asQuery(), function() {
        return res.send(this["export"]());
      });
    });
    server.post('/conditions/:fact-type/:condition-id', Condition_Model.route, function(req, res, next) {
      delete req.body._id;
      req.body.fact_type = req.params['fact-type'];
      req.body.condition_id = req.params['condition-id'];
      return req.model.update(req.params.asQuery(), req.body, ErrorHandler(next, function(err, updated) {
        return res.send({
          status: 'ok',
          statusText: 'The condition was ' + (updated && 'updated.' || 'created.'),
          condition: this["export"]()
        });
      }));
    });
    server.del('/conditions/:fact-type/:condition-id', Condition_Model.route, function(req, res, next) {
      return req.model.load(req.params.asQuery(), ErrorHandler(next, function(err, found) {
        if (found) {
          this.remove();
          return res.send({
            status: "ok",
            statusText: "The condition was removed."
          });
        } else {
          return res.send(404, {
            status: "warning",
            statusText: "No such condition exists, so it was not removed."
          });
        }
      }));
    });
    evaluate = function(next, res, fact, condition) {
      var _this = this;
      return fact.addShim(function() {
        return fact.evaluateCondition(condition, function(err, results) {
          return next(err || res.send({
            condition: condition["export"](),
            fact: fact["export"](),
            result: results.every(Boolean),
            result_breakdown: results
          }));
        });
      });
    };
    server.post('/conditions/:fact-type/:condition-id/test', Condition_Model.route, function(req, res, next) {
      return req.model.load(req.params.asQuery('fact-type', 'condition-id'), function(err) {
        var condition;
        condition = this;
        return new Fact_deferred_Model(req.account, condition.data.fact_type, function() {
          return this["import"](req.body, function() {
            return evaluate(next, res, this, condition);
          });
        });
      });
    });
    return server.post('/conditions/:fact-type/:condition-id/test/:fact-id', Condition_Model.route, function(req, res, next) {
      return req.model.load(req.params.asQuery('fact-type', 'condition-id'), function(err) {
        var condition;
        condition = this;
        return new Fact_deferred_Model(req.account, condition.data.fact_type, function() {
          return this.load({
            _id: req.params['fact-id']
          }, ErrorHandler(next, function(err) {
            return evaluate(next, res, this, condition);
          }));
        });
      });
    });
  };

}).call(this);

/*
//@ sourceMappingURL=condition.map
*/
