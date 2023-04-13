# frozen_string_literal: true

require 'redis'

# Redis session storage for Rails, and for Rails only. Derived from
# the MemCacheStore code, simply dropping in Redis instead.
class RedisSessionStore < ActionDispatch::Session::AbstractSecureStore
  VERSION = '0.12-18f'.freeze

  # ==== Options
  # * +:key+ - Same as with the other cookie stores, key name
  # * +:redis+ - A hash with redis-specific options
  #   * +:url+ - Redis url, default is redis://localhost:6379/0
  #   * +:key_prefix+ - Prefix for keys used in Redis, e.g. +myapp:+
  #   * +:ttl+ - Default Redis TTL for sessions
  #   * +:expire_after+ - A number in seconds for session timeout
  #   * +:client+ - Connect to Redis with given object rather than create one
  #   * +:client_pool:+ - Connect to Redis with a ConnectionPool
  # * +:on_redis_down:+ - Called with err, env, and SID on Errno::ECONNREFUSED
  # * +:on_session_load_error:+ - Called with err and SID on Marshal.load fail
  # * +:serializer:+ - Serializer to use on session data, default is :marshal.
  #
  # ==== Examples
  #
  #     Rails.application.config.session_store :redis_session_store,
  #       key: 'your_session_key',
  #       redis: {
  #         expire_after: 120.minutes,
  #         key_prefix: 'myapp:session:',
  #         url: 'redis://localhost:6379/0'
  #       },
  #       on_redis_down: ->(*a) { logger.error("Redis down! #{a.inspect}") },
  #       serializer: :hybrid # migrate from Marshal to JSON
  #
  def initialize(app, options = {})
    super

    @default_options[:namespace] = 'rack:session'
    @default_options.merge!(options[:redis] || {})
    redis_options = options[:redis] || {}
    if redis_options[:client_pool]
      @redis_pool = redis_options[:client_pool]
    else
      init_options = redis_options.reject { |k, _v| %i[expire_after key_prefix].include?(k) } || {}
      @single_redis = init_options[:client] || Redis.new(init_options)
    end
    @on_redis_down = options[:on_redis_down]
    @serializer = determine_serializer(options[:serializer])
    @on_session_load_error = options[:on_session_load_error]
    @default_redis_ttl = redis_options[:ttl]
    @write_fallback = redis_options[:write_fallback]
    @read_fallback = redis_options[:read_fallback]
    verify_handlers!
  end

  attr_accessor :on_redis_down, :on_session_load_error

  private

  attr_reader :redis_pool, :single_redis, :key, :default_options, :serializer, :default_redis_ttl, :read_fallback, :write_fallback

  def verify_handlers!
    %w(on_redis_down on_session_load_error).each do |h|
      next unless (handler = public_send(h)) && !handler.respond_to?(:call)

      raise ArgumentError, "#{h} handler is not callable"
    end
  end

  def prefixed(sid)
    return nil unless sid && sid.private_id
    "#{default_options[:key_prefix]}#{sid.private_id}"
  end

  def prefixed_fallback(sid)
    "#{default_options[:key_prefix]}#{sid}"
  end

  def create_sid(req)
    req.env['redis_session_store.new_session'] = true
    generate_sid
  end

  # @api public
  def find_session(req, sid)
    with_redis_connection do |redis_connection|
      existing_session = load_session_from_redis(redis_connection, req, sid)
      return [sid, existing_session] unless existing_session.nil?

      [create_sid(req), {}]
    end || [nil, {}]
  end

  def load_session_from_redis(redis_connection, req, sid)
    return nil unless sid
    if read_fallback
      data = redis_connection.get(prefixed(sid)) || redis_connection.get(prefixed_fallback(sid))
    else
      data = redis_connection.get(prefixed(sid))
    end

    begin
      data ? decode(data) : nil
    rescue StandardError => e
      delete_session_from_redis(redis_connection, sid, req, { drop: true })
      on_session_load_error.call(e, sid) if on_session_load_error
      nil
    end
  end

  def decode(data)
    serializer.load(data)
  end

  # @api public
  def write_session(req, sid, session_data, options = nil)
    return false unless sid

    if write_fallback
      key = prefixed_fallback(sid)
    else
      key = prefixed(sid)
    end
    return false unless key

    expiry = options[:expire_after] || default_redis_ttl
    new_session = req.env['redis_session_store.new_session']

    result = with_redis_connection(default_rescue_value: false) do |redis_connection|
      if expiry && new_session
        redis_connection.set(key, encode(session_data), ex: expiry, nx: true)
      elsif expiry
        redis_connection.set(key, encode(session_data), ex: expiry)
      elsif new_session
        redis_connection.set(key, encode(session_data), nx: true)
      else
        redis_connection.set(key, encode(session_data))
      end
    end

    if result
      sid
    else
      false
    end
  end

  def encode(session_data)
    serializer.dump(session_data)
  end

  # @api public
  def delete_session(req, sid, options)
    with_redis_connection do |redis_connection|
      delete_session_from_redis(redis_connection, sid, req, options)
    end
  end

  def delete_session_from_redis(redis_connection, sid, req, options)
    if write_fallback
      redis_connection.del(prefixed_fallback(sid))
    end

    redis_connection.del(prefixed(sid))

    create_sid(req) unless options[:drop]
  end

  def determine_serializer(serializer)
    serializer ||= :marshal
    case serializer
    when :marshal then Marshal
    when :json    then JsonSerializer
    else serializer
    end
  end

  # Consistent interface for a redis instance from a pool
  # @yield [Redis]
  def with_redis_connection(default_rescue_value: nil)
    if redis_pool
      redis_pool.with do |redis|
        yield redis
      end
    else
      yield single_redis
    end
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError => e
    on_redis_down.call(e) if on_redis_down
    default_rescue_value
  end

  # Uses built-in JSON library to encode/decode session
  class JsonSerializer
    def self.load(value)
      JSON.parse(value, quirks_mode: true)
    end

    def self.dump(value)
      JSON.generate(value, quirks_mode: true)
    end
  end
end
