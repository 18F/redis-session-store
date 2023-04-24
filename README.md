# Redis Session Store

This is a forked version of the [redis-session-store](https://github.com/roidrage/redis-session-store) gem. It incorporates a few changes:

* Configuring usage of a Redis connection pool.
* Passing the `nx: true` option when writing a new session to avoid session collisions.
* Supporting the migration towards hashed session identifiers to more fully address [GHSA-hrqr-hxpp-chr3](https://github.com/advisories/GHSA-hrqr-hxpp-chr3).
* Removes calling `exists` in Redis to check whether a session exists and instead relying on the result of `get`.

## Installation

``` ruby
gem 'redis-session-store', git: 'https://github.com/18F/redis-session-store.git', tag: 'v1.0.1-18f'
```

## Migrating from Rack::Session::SessionId#public_id to Rack::Session::SessionId#private_id

[GHSA-hrqr-hxpp-chr3](https://github.com/advisories/GHSA-hrqr-hxpp-chr3) describes a vulnerability to a timing attack when a key used by the backing store is the same key presented to the client. `redis-session-store` (as of the most recent version 0.11.5) writes the same key to Redis as is presented to the client, typically in the cookie. To allow for a backwards and forwards-compatible zero-downtime migration from `redis-session-store` and using `Rack::Session::SessionId#private_id` to remediate the vulnerability, this forked version provides configuration options to read and write the two versions of the session identifier. A migration path would typically look like:

1. Deploying with the following configuration, which is backwards-compatible:

```ruby
Rails.application.config.session_store :redis_session_store,
  # ...
  redis: {
   # ...
   read_fallback: true,
   write_fallback: true,
   read_primary: false,
   write_primary: false,
  }
```

2. Enabling writing to the primary key

```ruby
Rails.application.config.session_store :redis_session_store,
  # ...
  redis: {
   # ...
   read_fallback: true,
   write_fallback: true,
   read_primary: false,
   write_primary: true,
  }
```

3. Enabling reading the primary key

```ruby
Rails.application.config.session_store :redis_session_store,
  # ...
  redis: {
   # ...
   read_fallback: true,
   write_fallback: true,
   read_primary: true,
   write_primary: true,
  }
```

4. Disabling reading and writing for the fallback key

```ruby
Rails.application.config.session_store :redis_session_store,
  # ...
  redis: {
   # ...
   read_fallback: false,
   write_fallback: false,
   read_primary: true,
   write_primary: true,
  }
```

## Configuration

See `lib/redis-session-store.rb` for a list of valid options.
In your Rails app, throw in an initializer with the following contents:

``` ruby
Rails.application.config.session_store :redis_session_store,
  key: 'your_session_key',
  redis: {
    expire_after: 120.minutes,  # cookie expiration
    ttl: 120.minutes,           # Redis expiration, defaults to 'expire_after'
    key_prefix: 'myapp:session:',
    url: 'redis://localhost:6379/0',
  }
```

### Redis unavailability handling

If you want to handle cases where Redis is unavailable, a custom
callable handler may be provided as `on_redis_down`:

``` ruby
Rails.application.config.session_store :redis_session_store,
  # ... other options ...
  on_redis_down: ->(e, env, sid) { do_something_will_ya!(e) }
  redis: {
    # ... redis options ...
  }
```

### Serializer

By default the Marshal serializer is used. With Rails 4, you can use JSON as a
custom serializer:

* `:marshal` - serialize cookie values with `Marshal` (Default)
* `:json` - serialize cookie values with `JSON`
* `CustomClass` - You can just pass the constant name of a class that responds to `.load` and `.dump`

``` ruby
Rails.application.config.session_store :redis_session_store,
  # ... other options ...
  serializer: :json
  redis: {
    # ... redis options ...
  }
```

### Session load error handling

If you want to handle cases where the session data cannot be loaded, a
custom callable handler may be provided as `on_session_load_error` which
will be given the error and the session ID.

``` ruby
Rails.application.config.session_store :redis_session_store,
  # ... other options ...
  on_session_load_error: ->(e, sid) { do_something_will_ya!(e) }
  redis: {
    # ... redis options ...
  }
```

**Note** The session will *always* be destroyed when it cannot be loaded.

## Contributing, Authors, & License

See [CONTRIBUTING.md](CONTRIBUTING.md), [AUTHORS.md](AUTHORS.md), and
[LICENSE](LICENSE), respectively.
