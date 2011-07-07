Yo dawg. I herd you liek resque...

coffee-resque-scheduler
The start of a Resque Scheduler port to Node.js, CoffeeScript, and coffee-resque.

Current known limitations:

Doesn't support defined schedules yet (no schedule file).
  - It's comming, I just don't have a timeline.
    enqueueAt and enqueueOn were what I needed, so that's 
    what I started with.

Much like a worker in coffee-resque, the scheduler will emit events while it's running.