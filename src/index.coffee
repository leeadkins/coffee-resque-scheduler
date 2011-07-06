Helpers =
  rTimestamp: (timestamp) ->
    if typeof(timestamp) == 'object' && typeof(timestamp.getTime())
      rTimestamp = timestamp.getTime() / 1000
    else if typeof(timestamp) == 'number'
      rTimestamp = timestamp / 1000
    else
      throw "Invalid timestamp provide. Should be either a Date object or a number."
    rTimestamp

# Maintains the actual queue that will be
# processing the scheduled jobs
class ResqueScheduler
  constructor: (Resque) ->
    @resque = Resque
    extendResque @resque

# This adds some new prototypes to the existing Resque.Connection
# object, so they can be used as normal in coffee-resque

extendResque = (Resque) ->
  Resque.Connection::enqueueAt = (queue, timestamp, command, args) ->
    item = JSON.stringify class: command, queue: queue, args: args || []
    @delayedPush timestamp, item
  
  Resque.Connection::enqueueIn = (queue, numberOfSecondsFromNow, command, args) ->
    newTime = new Date() + (numberOfSecondsFromNow * 1000)
    @enqueueAt queue, newTime, command, args
    
  Resque.Connection::delayedPush = (timestamp, item) ->
    rTimestamp = Helpers.rTimestamp timestamp
    
    @redis.rpush("delayed:#{rTimestamp}", item);
    @redis.zadd 'delayed_queue_schedule', rTimestamp, rTimestamp
  
  Resque.Connection::delayed_queue_schedule_size = (callback) ->
    redis.zcard 'delayed_queue_schedule', (err, size) ->
      if err
        callback(err)
      else
        callback(err, size)
    
  Resque.Connection::next_delayed_timestamp = (atTime, callback) ->
    time = Helpers.rTimestamp(if atTime then atTime else new Date())
    @redis.zrangebyscore 'delayed_queue_schedule', '0', time, (err, items) ->
      if err
        callback(err)
      else if items.length < 1
        callback("No timestamps to run.")
      else
        callback(err, items[0])
  

  Resque.Connection.next_item_for_timestamp = (timestamp, callback) ->
    key = "delayed:#{Helpers.rTimestamp(timestamp)}"
    
    redis.lpop key, (err, item) ->
      callback(err, item)
        
  
exports.schedulerUsing = (Resque) ->
  new exports.ResqueScheduler Resque || {}

exports.ResqueScheduler = ResqueScheduler
    
