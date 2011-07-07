EventEmitter = require('events').EventEmitter

Helpers =
  rTimestamp: (timestamp) ->
    if typeof(timestamp) == 'object' && typeof(timestamp.getTime())
      rTimestamp = timestamp.getTime() / 1000
    else if typeof(timestamp) == 'number'
      rTimestamp = timestamp / 1000
    else
      throw "Invalid timestamp provide. Should be either a Date object or a number."
    Math.floor rTimestamp

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

    @redis.rpush @resque.key("delayed:#{rTimestamp}"), item
    @redis.zadd @resque.key('delayed_queue_schedule'), rTimestamp, rTimestamp
    
  start: ->
    if not @running
      @running = true
      self = this
      @interval = setInterval ((->
        self.poll())), 5000     # Runs every five seconds
  
  end: (cb) ->
    @running = false
    clearInterval @interval
    @interval = null
    
  poll: ->
    # Calculate the current
    # Decide if there is/are timestamp(s) in the sorted list to operate on 
    # if there are, get pull them
    @nextDelayedTimestamp (err, timestamp) =>
      if !err && timestamp
        console.log "Got the timestamp, attempting to get enqueue somethings..."
        @enqueueDelayedItemsForTimestamp timestamp, (err) =>
          @nextDelayedTimestamp arguments.callee unless err?
    return
    
  nextDelayedTimestamp: (callback) ->
    time = Helpers.rTimestamp(new Date())
    @redis.zrangebyscore @resque.key('delayed_queue_schedule'), '-inf', time, 'limit', 0, 1, (err, items) ->
      if err || items == null || items.length == 0
        callback(err)
      else
        console.log "Returning the next timestamp that I found"
        callback(false, items[0])
        
  enqueueDelayedItemsForTimestamp: (timestamp, callback) ->
    @nextItemForTimestamp timestamp, (err, job) =>
      if !err && job
        console.log "About to attempt to requeue a job..."
        @transfer job
        @nextItemForTimestamp timestamp, arguments.callee
      else
        callback(err)
      
  
  nextItemForTimestamp: (timestamp, callback) ->
    key = @resque.key("delayed:#{timestamp}")
    @redis.lpop key, (err, job) =>
      @cleanupTimestamp timestamp
      if err
        callback err
      else
        console.log "Returning a job that I found in the queue."
        callback false, JSON.parse job

  transfer: (job) ->
    console.log "Queuing job: #{JSON.stringify job}"
    @resque.enqueue job.queue, job.class, job.args
  
  cleanupTimestamp: (timestamp) ->
    key = @resque.key("delayed:#{timestamp}")
    @redis.llen key, (err, len) =>
      if len == 0
        @redis.del key
        @redis.zrem @resque.key('delayed_queue_schedule'), timestamp
    
exports.schedulerUsing = (Resque) ->
  new exports.ResqueScheduler Resque || {}

exports.ResqueScheduler = ResqueScheduler
    
