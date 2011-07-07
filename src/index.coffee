EventEmitter = require('events').EventEmitter

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
# Most of the logic is ported over from the Ruby Resque Scheduler,
# so I tried to keep the names and rough functionality the same so
# the can be compatible and such.

class ResqueScheduler extends EventEmitter
  constructor: (Resque) ->
    @resque   = Resque
    @redis    = @resque.redis
    @running  = false
    @ready    = false
    @interval = null
    
  enqueueAt: (queue, timestamp, command, args) ->
    item = JSON.stringify class: command, queue: queue, args: args || []
    @delayedPush timestamp, item

  enqueueIn: (queue, numberOfSecondsFromNow, command, args) ->
    newTime = new Date() + (numberOfSecondsFromNow * 1000)
    @enqueueAt queue, newTime, command, args

  delayedPush: (timestamp, item) ->
    rTimestamp = Helpers.rTimestamp timestamp

    @redis.rpush @key("delayed:#{rTimestamp}"), item
    @redis.zadd @key('delayed_queue_schedule'), rTimestamp, rTimestamp
    
  start: ->
    if not @running
      @running = true
      @interval = setInterval poll, 5000     # Runs every five seconds
  
  end: (cb) ->
    @running = false
    clearInterval @interval
    @interval = null
    
  poll: ->
    return unless @running
    console.log "Polling..."
    # Calculate the current
    # Decide if there is/are timestamp(s) in the sorted list to operate on 
    # if there are, get pull them
    @nextDelayedTimestamp (err, timestamp) ->
      if timestamp?
        @enqueueDelayedItemsForTimestamp timestamp, (err) ->
          @nextDelayedTimestamp arguments.callee unless err?
    return
    
  nextDelayedTimestamp: (atTime, callback) ->
    time = Helpers.rTimestamp(if atTime then atTime else new Date())
    @redis.zrangebyscore 'delayed_queue_schedule', '-inf', time, 'limit', 0, 1, (err, items) ->
      if err || not items?
        callback(err)
      else
        callback(false, items[0])
        
  enqueueDelayedItemsForTimestamp: (timestamp, callback) ->
    @nextItemForTimestamp timestamp, (err, job) ->
      if not err? and job?
        @transfer job
        @nextItemForTimestamp timestamp, arguments.callee
      else
        callback(err)
      
  
  nextItemForTimestamp: (timestamp, callback) ->
    @redis.lpop "delayed:#{timestamp}", (err, job) ->
      cleanupTimestamp "delayed:#{timestamp}", timestamp
      if err
        callback err
      else
        callback false, JSON.parse job

  transfer: (job) ->
    console.log "Queuing job: #{JSON.stringify job}"
    @redis.enqueue job.queue, job.class, job.args
  
  cleanupTimestamp: (timestamp) ->
    redis.llen "delayed:#{timestamp}" (err, len) ->
      if length == 0
        @redis.del "delayed:#{timestamp}"
        @redis.zrem 'delayed_queue_schedule', timestamp
    
exports.schedulerUsing = (Resque) ->
  new exports.ResqueScheduler Resque || {}

exports.ResqueScheduler = ResqueScheduler
    
