module HealthCheck
  class RedisHealthCheck
    extend BaseHealthCheck

    def self.check
      unless defined?(::Redis)
        raise "Wrong configuration. Missing 'redis' gem"
      end
      res = ::Redis.new(url: HealthCheck.redis_url).ping
      return { error: !(res == 'PONG'), url: HealthCheck.redis_url, res: res.inspect }
    rescue Exception => e
      create_error 'redis', e.message
    end
  end
end
