module HealthCheck
  class EnvCheck
    extend BaseHealthCheck

    def self.check
      env_keys = HealthCheck.mandatory_env_keys
      missing_keys = []
      env_keys.each do |ek|
        env_val = ENV.fetch(ek, nil)
        missing_keys << ek unless env_val.present?
      end
      { error: missing_keys.present?, missing_keys: missing_keys }
    end
  end
end
