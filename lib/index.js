(function() {
  var Helpers, ResqueScheduler, extendResque;
  Helpers = {
    rTimestamp: function(timestamp) {
      var rTimestamp;
      if (typeof timestamp === 'object' && typeof (timestamp.getTime())) {
        rTimestamp = timestamp.getTime() / 1000;
      } else if (typeof timestamp === 'number') {
        rTimestamp = timestamp / 1000;
      } else {
        throw "Invalid timestamp provide. Should be either a Date object or a number.";
      }
      return rTimestamp;
    }
  };
  ResqueScheduler = (function() {
    function ResqueScheduler(Resque) {
      this.resque = Resque;
      extendResque(this.resque);
    }
    return ResqueScheduler;
  })();
  extendResque = function(Resque) {
    Resque.Connection.prototype.enqueueAt = function(queue, timestamp, command, args) {
      var item;
      item = JSON.stringify({
        "class": command,
        queue: queue,
        args: args || []
      });
      return this.delayedPush(timestamp, item);
    };
    Resque.Connection.prototype.enqueueIn = function(queue, numberOfSecondsFromNow, command, args) {
      var newTime;
      newTime = new Date() + (numberOfSecondsFromNow * 1000);
      return this.enqueueAt(queue, newTime, command, args);
    };
    Resque.Connection.prototype.delayedPush = function(timestamp, item) {
      var rTimestamp;
      rTimestamp = Helpers.rTimestamp(timestamp);
      this.redis.rpush("delayed:" + rTimestamp, item);
      return this.redis.zadd('delayed_queue_schedule', rTimestamp, rTimestamp);
    };
    Resque.Connection.prototype.delayed_queue_schedule_size = function(callback) {
      return redis.zcard('delayed_queue_schedule', function(err, size) {
        if (err) {
          return callback(err);
        } else {
          return callback(err, size);
        }
      });
    };
    Resque.Connection.prototype.next_delayed_timestamp = function(atTime, callback) {
      var time;
      time = Helpers.rTimestamp(atTime ? atTime : new Date());
      return this.redis.zrangebyscore('delayed_queue_schedule', '0', time, function(err, items) {
        if (err) {
          return callback(err);
        } else if (items.length < 1) {
          return callback("No timestamps to run.");
        } else {
          return callback(err, items[0]);
        }
      });
    };
    return Resque.Connection.next_item_for_timestamp = function(timestamp, callback) {
      var key;
      key = "delayed:" + (Helpers.rTimestamp(timestamp));
      return redis.lpop(key, function(err, item) {
        return callback(err, item);
      });
    };
  };
  exports.schedulerUsing = function(Resque) {
    return new exports.ResqueScheduler(Resque || {});
  };
  exports.ResqueScheduler = ResqueScheduler;
}).call(this);
