require 'json'
require 'connection_pool'
require 'rack/session/abstract/id'
require 'action_dispatch'
require 'action_dispatch/testing/test_request'

describe RedisSessionStore do
  subject(:store) { described_class.new(nil, options) }

  let :random_string do
    "#{rand}#{rand}#{rand}"
  end
  let :default_options do
    store.instance_variable_get(:@default_options)
  end

  let :options do
    {}
  end

  it 'assigns a :namespace to @default_options' do
    expect(default_options[:namespace]).to eq('rack:session')
  end

  describe 'when initializing with the redis sub-hash options' do
    let :options do
      {
        key: random_string,
        secret: random_string,
        redis: {
          host: 'hosty.local',
          port: 16_379,
          db: 2,
          key_prefix: 'myapp:session:',
          expire_after: 60 * 120
        }
      }
    end

    it 'creates a redis instance' do
      expect(store.instance_variable_get(:@single_redis)).not_to be_nil
    end

    it 'assigns the :host option to @default_options' do
      expect(default_options[:host]).to eq('hosty.local')
    end

    it 'assigns the :port option to @default_options' do
      expect(default_options[:port]).to eq(16_379)
    end

    it 'assigns the :db option to @default_options' do
      expect(default_options[:db]).to eq(2)
    end

    it 'assigns the :key_prefix option to @default_options' do
      expect(default_options[:key_prefix]).to eq('myapp:session:')
    end

    it 'assigns the :expire_after option to @default_options' do
      expect(default_options[:expire_after]).to eq(60 * 120)
    end

    context 'with a :client_pool' do
      let :options do
        {
          key: random_string,
          secret: random_string,
          redis: {
            client_pool: ConnectionPool.new(size: 2) { double('redis') }
          }
        }
      end

      it 'assigns the pool to @redis_pool' do
        expect(store.instance_variable_get(:@redis_pool)).
          to eq(options[:redis][:client_pool])
      end
    end
  end

  describe 'when configured with both :ttl and :expire_after' do
    let(:ttl_seconds) { 60 * 120 }
    let :options do
      {
        key: random_string,
        secret: random_string,
        redis: {
          host: 'hosty.local',
          port: 16_379,
          db: 2,
          key_prefix: 'myapp:session:',
          ttl: ttl_seconds,
          expire_after: nil
        }
      }
    end

    it 'assigns the :ttl option to @default_options' do
      expect(default_options[:ttl]).to eq(ttl_seconds)
      expect(default_options[:expire_after]).to be_nil
    end
  end

  describe 'when initializing with top-level redis options' do
    let :options do
      {
        key: random_string,
        secret: random_string,
        host: 'hostersons.local',
        port: 26_379,
        db: 4,
        key_prefix: 'appydoo:session:',
        expire_after: 60 * 60
      }
    end

    it 'creates a redis instance' do
      expect(store.instance_variable_get(:@single_redis)).not_to be_nil
    end

    it 'assigns the :host option to @default_options' do
      expect(default_options[:host]).to eq('hostersons.local')
    end

    it 'assigns the :port option to @default_options' do
      expect(default_options[:port]).to eq(26_379)
    end

    it 'assigns the :db option to @default_options' do
      expect(default_options[:db]).to eq(4)
    end

    it 'assigns the :key_prefix option to @default_options' do
      expect(default_options[:key_prefix]).to eq('appydoo:session:')
    end

    it 'assigns the :expire_after option to @default_options' do
      expect(default_options[:expire_after]).to eq(60 * 60)
    end
  end

  describe 'when initializing with existing redis object' do
    let :options do
      {
        key: random_string,
        secret: random_string,
        redis: {
          client: redis_client,
          key_prefix: 'myapp:session:',
          expire_after: 60 * 30
        }
      }
    end

    let(:redis_client) { double('redis_client') }

    it 'assigns given redis object to @single_redis' do
      expect(store.instance_variable_get(:@single_redis)).to be(redis_client)
    end

    it 'assigns the :client option to @default_options' do
      expect(default_options[:client]).to be(redis_client)
    end

    it 'assigns the :key_prefix option to @default_options' do
      expect(default_options[:key_prefix]).to eq('myapp:session:')
    end

    it 'assigns the :expire_after option to @default_options' do
      expect(default_options[:expire_after]).to eq(60 * 30)
    end
  end

  describe 'fetching a session' do
    let :options do
      {
        key_prefix: 'customprefix::'
      }
    end

    let(:fake_key) { Rack::Session::SessionId.new('thisisarediskey') }

    describe 'generate_sid' do
      it 'generates a secure ID' do
        sid = store.send(:generate_sid)
        expect(sid).to be_a(Rack::Session::SessionId)
      end
    end

    it 'retrieves the prefixed private_id key from redis when read_fallback is not enabled' do
      redis = double('redis')
      allow(store).to receive(:single_redis).and_return(redis)
      allow(store).to receive(:generate_sid).and_return(fake_key)
      expect(redis).to receive(:get).with("#{options[:key_prefix]}#{fake_key.private_id}").and_return(
        Marshal.dump(''),
      )

      store.send(:find_session, ActionDispatch::TestRequest.create, fake_key)
    end

    it 'retrieves the prefixed private_id key from redis when read_fallback is not enabled' do
      options[:redis] = { write_fallback: true }
      store = described_class.new(nil, options)
      redis = double('redis')
      allow(store).to receive(:single_redis).and_return(redis)
      allow(store).to receive(:generate_sid).and_return(fake_key)
      expect(redis).to receive(:get).with("#{options[:key_prefix]}#{fake_key.private_id}").and_return(
        Marshal.dump(''),
      )

      store.send(:find_session, ActionDispatch::TestRequest.create, fake_key)
    end

    it 'retrieves the prefixed public_id key from redis when read_fallback is enabled and the private_id key does not exist' do
      options[:redis] = { read_fallback: true }
      store = described_class.new(nil, options)
      redis = double('redis')
      allow(store).to receive(:single_redis).and_return(redis)
      allow(store).to receive(:generate_sid).and_return(fake_key)
      expect(redis).to receive(:get).with("#{options[:key_prefix]}#{fake_key.private_id}").and_return(
        nil
      )
      expect(redis).to receive(:get).with("#{options[:key_prefix]}#{fake_key.public_id}").and_return(
        Marshal.dump('')
      )

      store.send(:find_session, ActionDispatch::TestRequest.create, fake_key)
    end

    context 'when redis is down' do
      before do
        allow(store).to receive(:single_redis).and_raise(Redis::CannotConnectError)
        allow(store).to receive(:generate_sid).and_return('foop')
      end

      context 'when :on_redis_down re-raises' do
        before { store.on_redis_down = ->(e, *) { raise e } }

        it 'explodes' do
          expect do
            store.send(:find_session, ActionDispatch::TestRequest.create, fake_key)
          end.to raise_error(Redis::CannotConnectError)
        end
      end
    end
  end

  describe 'destroying a session' do
    context 'when destroyed via #destroy_session' do
      it 'deletes the prefixed private_id key from redis when write_fallback is not enabled' do
        redis = double('redis')
        allow(store).to receive(:single_redis).and_return(redis)
        sid = store.send(:generate_sid)
        expect(redis).to receive(:del).with("#{options[:key_prefix]}#{sid.private_id}")

        store.send(:delete_session, {}, sid, { drop: true })
      end

      it 'deletes the prefixed private_id and public_id keys from redis when write_fallback is enabled' do
        store = described_class.new(nil, { redis: { write_fallback: true } })
        redis = double('redis')
        allow(store).to receive(:single_redis).and_return(redis)
        sid = store.send(:generate_sid)
        expect(redis).to receive(:del).with("#{options[:key_prefix]}#{sid.private_id}")
        expect(redis).to receive(:del).with("#{options[:key_prefix]}#{sid.public_id}")

        store.send(:delete_session, {}, sid, { drop: true })
      end
    end
  end

  describe 'session encoding' do
    let(:env)          { ActionDispatch::TestRequest.create }
    let(:session_id)   { Rack::Session::SessionId.new('thisisarediskey') }
    let(:session_data) { { 'some' => 'data' } }
    let(:options)      { {} }
    let(:encoded_data) { Marshal.dump(session_data) }
    let(:redis)        { double('redis', set: nil, get: encoded_data) }
    let(:expected_encoding) { encoded_data }

    before do
      allow(store).to receive(:single_redis).and_return(redis)
    end

    shared_examples_for 'serializer' do
      it 'encodes correctly' do
        expect(redis).to receive(:set).with(session_id.private_id, expected_encoding)
        store.send(:write_session, env, session_id, session_data, options)
      end

      it 'decodes correctly' do
        expect(store.send(:find_session, env, session_id))
          .to eq([session_id, session_data])
      end
    end

    context 'marshal' do
      let(:options) { { serializer: :marshal } }

      it_behaves_like 'serializer'
    end

    context 'json' do
      let(:options) { { serializer: :json } }
      let(:encoded_data) { '{"some":"data"}' }

      it_behaves_like 'serializer'
    end

    context 'custom' do
      let :custom_serializer do
        Class.new do
          def self.load(_value)
            { 'some' => 'data' }
          end

          def self.dump(_value)
            'somedata'
          end
        end
      end

      let(:options) { { serializer: custom_serializer } }
      let(:expected_encoding) { 'somedata' }

      it_behaves_like 'serializer'
    end
  end

  describe 'handling decode errors' do
    let(:fake_key) { Rack::Session::SessionId.new('thisisarediskey') }
    let(:fake_redis) { double('redis',
                             get: "\x04\bo:\nNonExistentClass\x00",
                             set: true,
                             del: true) }
    context 'when a class is serialized that does not exist' do
      before do
        allow(store).to receive(:single_redis)
          .and_return(fake_redis)
      end

      it 'returns an empty session' do
        expect(store.send(:find_session, ActionDispatch::TestRequest.create, fake_key).last).to eq({})
      end

      it 'destroys and drops the session' do
        req = ActionDispatch::TestRequest.create
        expect(store).to receive(:delete_session_from_redis)
          .with(fake_redis, fake_key, req, { drop: true })
        store.send(:find_session, req, fake_key)
      end

      context 'when a custom on_session_load_error handler is provided' do
        before do
          store.on_session_load_error = lambda do |e, sid|
            @e = e
            @sid = sid
          end
        end

        it 'passes the error and the sid to the handler' do
          store.send(:find_session, ActionDispatch::TestRequest.create, fake_key)
          expect(@e).to be_kind_of(StandardError)
          expect(@sid).to eq(fake_key)
        end
      end
    end

    context 'when the encoded data is invalid' do
      let(:fake_redis) { double('redis',
                             get: "\x00\x00\x00\x00",
                             set: true,
                             del: true) }
      before do
        allow(store).to receive(:single_redis)
          .and_return(fake_redis)
      end

      it 'returns an empty session' do
        expect(store.send(:find_session, ActionDispatch::TestRequest.create, fake_key).last).to eq({})
      end

      it 'destroys and drops the session' do
        req = ActionDispatch::TestRequest.create
        expect(store).to receive(:delete_session_from_redis)
          .with(fake_redis, fake_key, req, { drop: true })
        store.send(:find_session, req, fake_key)
      end

      context 'when a custom on_session_load_error handler is provided' do
        before do
          store.on_session_load_error = lambda do |e, sid|
            @e = e
            @sid = sid
          end
        end

        it 'passes the error and the sid to the handler' do
          store.send(:find_session, ActionDispatch::TestRequest.create, fake_key)
          expect(@e).to be_kind_of(StandardError)
          expect(@sid).to eq(fake_key)
        end
      end
    end
  end

  describe 'validating custom handlers' do
    %w(on_redis_down on_session_load_error).each do |h|
      context 'when nil' do
        it 'does not explode at init' do
          expect { store }.not_to raise_error
        end
      end

      context 'when callable' do
        let(:options) { { "#{h}": ->(*) { true } } }

        it 'does not explode at init' do
          expect { store }.not_to raise_error
        end
      end

      context 'when not callable' do
        let(:options) { { "#{h}": 'herpderp' } }

        it 'explodes at init' do
          expect { store }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe 'setting the session' do
    it 'allows changing the session' do
      env = { 'rack.session.options' => {} }
      req = ActionDispatch::TestRequest.create(env)
      sid = Rack::Session::SessionId.new('thisisarediskey')
      allow(store).to receive(:single_redis).and_return(Redis.new)
      data1 = { 'foo' => 'bar' }
      store.send(:write_session, req, sid, data1, {})
      data2 = { 'baz' => 'wat' }
      store.send(:write_session, req, sid, data2, {})
      _, session = store.send(:find_session, req, sid)
      expect(session).to eq(data2)
    end

    it 'allows changing the session when the session has an expiry' do
      env = { 'rack.session.options' => { expire_after: 60 } }
      req = ActionDispatch::TestRequest.create(env)
      sid = Rack::Session::SessionId.new('thisisarediskey')
      allow(store).to receive(:single_redis).and_return(Redis.new)
      data1 = { 'foo' => 'bar' }
      store.send(:write_session, req, sid, data1, {})
      data2 = { 'baz' => 'wat' }
      store.send(:write_session, req, sid, data2, {})
      _, session = store.send(:find_session, req, sid)
      expect(session).to eq(data2)
    end

    it 'writes to public_id if write_fallback is enabled' do
      store = described_class.new(nil, { redis: { write_fallback: true } })
      redis = double('redis')
      req = ActionDispatch::TestRequest.create({})
      sid = Rack::Session::SessionId.new('thisisarediskey')
      allow(store).to receive(:single_redis).and_return(redis)
      data1 = { 'foo' => 'bar' }
      expect(redis).to receive(:set).with("#{options[:key_prefix]}#{sid.public_id}", instance_of(String))

      store.send(:write_session, req, sid, data1, {})
    end

    it 'writes to private_id if write_fallback is not enabled' do
      redis = double('redis')
      req = ActionDispatch::TestRequest.create({})
      sid = Rack::Session::SessionId.new('thisisarediskey')
      allow(store).to receive(:single_redis).and_return(redis)
      data1 = { 'foo' => 'bar' }
      expect(redis).to receive(:set).with("#{options[:key_prefix]}#{sid.private_id}", instance_of(String))

      store.send(:write_session, req, sid, data1, {})
    end
  end
end
