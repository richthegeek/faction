# Shared Cache

Allow applications share cache-state and data over Redis.

# Usage
```
function update_info(cache_key, next) {
    db.findOne({}, next)
}

Cache = require('shared-cache')
info = Cache.create('caching key', true, update_info)

possibly_stale = info.get();
info.get(function(err, definitely_not_stale) {
    ...
})
```

# Methods

## create( key, auto_update, update_callback )
Returns a caching instance from the singleton pool.

## get( [callback] )
This function both returns and executes a callback.
 - In the event the data is not stale, both will receive the same value.
 - If the data is stale, the return will be the stale value whilst the callback is held until the data is available.

## set( data, broadcast = true )
Update the value of this cache, optionally broadcasting the new value to other instances. This marks the data as not stale.

## update( callback )
Add the callback onto a queue to be fired when the update_callback returns, and call the update_callback if it hasn't already been called.

## stale( broadcast = true )
Mark this data as stale. If auto_update is true then it update_callback is fired. If broadcast is true, other instances are notified to update their caches.
