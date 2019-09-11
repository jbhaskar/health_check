module HealthCheck
  class S3HealthCheck
    extend BaseHealthCheck

    class << self
      def check
        unless defined?(::Aws)
          raise "Wrong configuration. Missing 'aws-sdk' gem"
        end
        return create_error 's3', 'Region is not set' if aws_s3_client.config.blank? || aws_s3_client.config[:region].blank?
        return create_error 's3', 'Could not connect to aws' if aws_s3_client.nil?
        res = { error: false }
        HealthCheck.buckets.each do |bucket_name, permissions|
          begin
            res[bucket_name] = { connected: aws_s3_client.head_bucket(bucket: bucket_name).to_h }
            permissions = [:R, :W, :D] if permissions.nil? # backward compatible
            permissions.each do |permision|
              begin
                res[bucket_name][permision] = send(permision, bucket_name).present?
              rescue => e
                res[bucket_name][permision] = { error: true, error_message: e.message }
                res[:error] = true
              end
            end
          rescue => e
            res[bucket_name] = { error: true, error_message: e.message }
            res[:error] = true
          end
        end
        { error: res[:error], buckets: HealthCheck.buckets, res: res }
      rescue Exception => e
        create_error 's3', e.message
      end

      private

      def configure_client
        return unless defined?(Rails)
        # aws_configuration = {
        #   region: Rails.application.secrets.aws_default_region,
        #   credentials: ::Aws::Credentials.new(
        #     Rails.application.secrets.aws_access_key_id,
        #     Rails.application.secrets.aws_secret_access_key
        #   ),
        #   force_path_style: true
        # }
        ::Aws::S3::Client.new(retry_limit: 1)#aws_configuration
      end

      def aws_s3_client
        @aws_s3_client ||= configure_client
      end

      def R(bucket)
        aws_s3_client.list_objects(bucket: bucket)
      end

      def W(bucket)
        aws_s3_client.put_object(bucket: bucket,
                                 key: "healthcheck_#{Rails.application.class.parent_name}",
                                 body: Time.new.to_s)
      end

      def D(bucket)
        aws_s3_client.delete_object(bucket: bucket,
                                    key: "healthcheck_#{Rails.application.class.parent_name}")
      end
    end
  end
end
