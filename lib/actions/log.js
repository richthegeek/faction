// Generated by CoffeeScript 1.6.3
module.exports = {
  name: 'log',
  description: 'Simply log some information',
  validate: function(action, callback) {
    return callback('I cant do that dave');
    return callback(null, true);
  },
  exec: function(info, next) {
    return next(null, info.step.message);
  }
};