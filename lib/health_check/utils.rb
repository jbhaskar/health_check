# Copyright (c) 2010-2013 Ian Heggie, released under the MIT license.
# See MIT-LICENSE for details.

module HealthCheck
  class Utils

    @@default_smtp_settings =
        {
            :address              => "localhost",
            :port                 => 25,
            :domain               => 'localhost.localdomain',
            :user_name            => nil,
            :password             => nil,
            :authentication       => nil,
            :enable_starttls_auto => true,
        }

    cattr_accessor :default_smtp_settings

    # process an array containing a list of checks
    def self.process_checks(checks, called_from_middleware = false)
      res = { error: false }
      checks.each do |check|
        case check
          when 'and', 'site'
            # do nothing
          when "database"
            database_version = HealthCheck::Utils.get_database_version
            res[check] = { error: database_version.blank?, version: database_version }
          when "email"
            res = HealthCheck::Utils.check_email
            res[check] = { error: res.present?, res: res }
          when "emailconf"
            res[check] = HealthCheck::Utils.check_email if HealthCheck::Utils.mailer_configured?
            res[check] = { error: res.present?, res: res }
          when "migrations", "migration"
            if defined?(ActiveRecord::Migration) and ActiveRecord::Migration.respond_to?(:check_pending!)
              begin
                res[check] = { error: false, pending: ActiveRecord::Migration.check_pending! }
              rescue ActiveRecord::PendingMigrationError => ex
                res[check] = { error: true, error_message: ex.message }
              end
            else
              database_version  = HealthCheck::Utils.get_database_version
              migration_version = HealthCheck::Utils.get_migration_version
              if database_version.to_i != migration_version.to_i
                res[check] = {
                  error: true,
                  database_version: database_version,
                  migration_version: migration_version,
                  error_message: "Current database version (#{database_version}) does not match latest migration (#{migration_version}). "
                }
              end
            end
          when 'env'
            res[check] = HealthCheck::EnvCheck.check
          when 'cache'
            res[check] = HealthCheck::Utils.check_cache
          when 'resque-redis-if-present'
            res[check] = HealthCheck::ResqueHealthCheck.check if defined?(::Resque)
          when 'sidekiq-redis-if-present'
            res[check] = HealthCheck::SidekiqHealthCheck.check if defined?(::Sidekiq)
          when 'redis-if-present'
            res[check] = HealthCheck::RedisHealthCheck.check if defined?(::Redis)
          when 's3-if-present'
            res[check] = HealthCheck::S3HealthCheck.check if defined?(::Aws)
          when 'resque-redis'
            res[check] = HealthCheck::ResqueHealthCheck.check
          when 'sidekiq-redis'
            res[check] = HealthCheck::SidekiqHealthCheck.check
          when 'redis'
            res[check] = HealthCheck::RedisHealthCheck.check
          when 's3'
            res[check] = HealthCheck::S3HealthCheck.check
          when "standard"
            res[check] = HealthCheck::Utils.process_checks(HealthCheck.standard_checks, called_from_middleware)
          when "middleware"
            unless called_from_middleware
              res[check] = "Health check not called from middleware - probably not installed as middleware." 
              res[:error] = true
            end
          when "custom"
            HealthCheck.custom_checks.each do |name, list|
              res[name] = []
              list.each do |custom_check|
                res[name] << custom_check.call(self)
              end
            end
          when "all", "full"
            res[check] = HealthCheck::Utils.process_checks(HealthCheck.full_checks, called_from_middleware)
          else
            if HealthCheck.custom_checks.include? check
              res[check] = []
              HealthCheck.custom_checks[check].each do |custom_check|
               res[check] << custom_check.call(self)
              end
              res
            else
              res = { error: true, msg: "invalid argument to health_test." }
            end
        end
        res[:error] ||= res[check][:error] if res[check].present?
      end
      return res
    rescue => e
      return { error: true, msg: e.message }
    end

    def self.db_migrate_path
      # Lazy initialisation so Rails.root will be defined
      @@db_migrate_path ||= File.join(Rails.root, 'db', 'migrate')
    end

    def self.db_migrate_path=(value)
      @@db_migrate_path = value
    end

    def self.mailer_configured?
      defined?(ActionMailer::Base) && (ActionMailer::Base.delivery_method != :smtp || HealthCheck::Utils.default_smtp_settings != ActionMailer::Base.smtp_settings)
    end

    def self.get_database_version
      ActiveRecord::Migrator.current_version if defined?(ActiveRecord)
    end

    def self.get_migration_version(dir = self.db_migrate_path)
      latest_migration = nil
      Dir[File.join(dir, "[0-9]*_*.rb")].each do |f|
        l = f.scan(/0*([0-9]+)_[_.a-zA-Z0-9]*.rb/).first.first rescue -1
        latest_migration = l if !latest_migration || l.to_i > latest_migration.to_i
      end
      latest_migration
    end

    def self.check_email
      case ActionMailer::Base.delivery_method
        when :smtp
          HealthCheck::Utils.check_smtp(ActionMailer::Base.smtp_settings, HealthCheck.smtp_timeout)
        when :sendmail
          HealthCheck::Utils.check_sendmail(ActionMailer::Base.sendmail_settings)
        else
          ''
      end
    end

    def self.check_sendmail(settings)
      File.executable?(settings[:location]) ? '' : 'no sendmail executable found. '
    end

    def self.check_smtp(settings, timeout)
      status = ''
      begin
        if @skip_external_checks
          status = '221'
        else
          Timeout::timeout(timeout) do |timeout_length|
            t = TCPSocket.new(settings[:address], settings[:port])
            begin
              status = t.gets
              while status != nil && status !~ /^2/
                status = t.gets
              end
              t.puts "HELO #{settings[:domain]}\r"
              while status != nil && status !~ /^250/
                status = t.gets
              end
              t.puts "QUIT\r"
              status = t.gets
            ensure
              t.close
            end
          end
        end
      rescue Errno::EBADF => ex
        status = "Unable to connect to service"
      rescue Exception => ex
        status = ex.to_s
      end
      (status =~ /^221/) ? '' : "SMTP: #{status || 'unexpected EOF on socket'}. "
    end

    def self.check_cache
      Rails.cache.write('__health_check_cache_test__', 'ok', :expires_in => 1.second) ? '' : 'Unable to write to cache. '
    end

  end
end
