(function() {
  var EventEmitter, Helpers, ResqueScheduler;
  var __hasProp = Object.prototype.hasOwnProperty, __extends = function(child, parent) {
    for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; }
    function ctor() { this.constructor = child; }
    ctor.prototype = parent.prototype;
    child.prototype = new ctor;
    child.__super__ = parent.prototype;
    return child;
  }, __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  EventEmitter = require('events').EventEmitter;
  Helpers = {
    rTimestamp: function(timestamp) {
      var rTimestamp;
      if (typeof timestamp === 'object' && typeof (timestamp.getTime()) !== 'undefined') {
        rTimestamp = timestamp.getTime() / 1000;
      } else if (typeof timestamp === 'number') {
        rTimestamp = timestamp / 1000;
      } else {
        throw "Invalid timestamp provide. Should be either a Date object or a number.";
      }
      return Math.floor(rTimestamp);
    }
  };
  ResqueScheduler = (function() {
    __extends(ResqueScheduler, EventEmitter);
    function ResqueScheduler(Resque) {
      this.resque = Resque;
      this.redis = this.resque.redis;
      this.running = false;
      this.ready = false;
      this.interval = null;
    }
    ResqueScheduler.prototype.enqueueAt = function(queue, timestamp, command, args) {
      var item;
      item = JSON.stringify({
        "class": command,
        queue: queue,
        args: args || []
      });
      return this.delayedPush(timestamp, item);
    };
    ResqueScheduler.prototype.enqueueIn = function(queue, numberOfSecondsFromNow, command, args) {
      var newTime;
      newTime = new Date().getTime() + (numberOfSecondsFromNow * 1000);
      return this.enqueueAt(queue, newTime, command, args);
    };
    ResqueScheduler.prototype.delayedPush = function(timestamp, item) {
      var rTimestamp;
      rTimestamp = Helpers.rTimestamp(timestamp);
      this.redis.rpush(this.resque.key("delayed:" + rTimestamp), item);
      return this.redis.zadd(this.resque.key('delayed_queue_schedule'), rTimestamp, rTimestamp);
    };
    ResqueScheduler.prototype.start = function() {
      var self;
      if (!this.running) {
        this.running = true;
        self = this;
        return this.interval = setInterval((function() {
          return self.poll();
        }), 5000);
      }
    };
    ResqueScheduler.prototype.end = function(cb) {
      this.running = false;
      clearInterval(this.interval);
      return this.interval = null;
    };
    ResqueScheduler.prototype.poll = function() {
      this.nextDelayedTimestamp(__bind(function(err, timestamp) {
        if (!err && timestamp) {
          console.log("Got the timestamp, attempting to get enqueue somethings...");
          return this.enqueueDelayedItemsForTimestamp(timestamp, __bind(function(err) {
            if (err == null) {
              return this.nextDelayedTimestamp(arguments.callee);
            }
          }, this));
        }
      }, this));
    };
    ResqueScheduler.prototype.nextDelayedTimestamp = function(callback) {
      var time;
      time = Helpers.rTimestamp(new Date());
      return this.redis.zrangebyscore(this.resque.key('delayed_queue_schedule'), '-inf', time, 'limit', 0, 1, function(err, items) {
        if (err || items === null || items.length === 0) {
          return callback(err);
        } else {
          console.log("Returning the next timestamp that I found");
          return callback(false, items[0]);
        }
      });
    };
    ResqueScheduler.prototype.enqueueDelayedItemsForTimestamp = function(timestamp, callback) {
      return this.nextItemForTimestamp(timestamp, __bind(function(err, job) {
        if (!err && job) {
          console.log("About to attempt to requeue a job...");
          this.transfer(job);
          return this.nextItemForTimestamp(timestamp, arguments.callee);
        } else {
          return callback(err);
        }
      }, this));
    };
    ResqueScheduler.prototype.nextItemForTimestamp = function(timestamp, callback) {
      var key;
      key = this.resque.key("delayed:" + timestamp);
      return this.redis.lpop(key, __bind(function(err, job) {
        this.cleanupTimestamp(timestamp);
        if (err) {
          return callback(err);
        } else {
          console.log("Returning a job that I found in the queue.");
          return callback(false, JSON.parse(job));
        }
      }, this));
    };
    ResqueScheduler.prototype.transfer = function(job) {
      console.log("Queuing job: " + (JSON.stringify(job)));
      return this.resque.enqueue(job.queue, job["class"], job.args);
    };
    ResqueScheduler.prototype.cleanupTimestamp = function(timestamp) {
      var key;
      key = this.resque.key("delayed:" + timestamp);
      return this.redis.llen(key, __bind(function(err, len) {
        if (len === 0) {
          this.redis.del(key);
          return this.redis.zrem(this.resque.key('delayed_queue_schedule'), timestamp);
        }
      }, this));
    };
    return ResqueScheduler;
  })();
  exports.schedulerUsing = function(Resque) {
    return new exports.ResqueScheduler(Resque || {});
  };
  exports.ResqueScheduler = ResqueScheduler;
}).call(this);
