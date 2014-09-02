# name: api_sso
# about: Allow API to create a user for Single Sign On.
# version: 0.1
# authors: Gautham

load File.expand_path("../api_sso.rb", __FILE__)
ApiSso = ApiSso

after_initialize do
  # Rails Engine.
  module ApiSso
    class Engine < ::Rails::Engine
      engine_name "api_sso"
      isolate_namespace ApiSso
    end


    class ApiSsoController < ActionController::Base
      include CurrentUser

      def register_user
        # Obtain the SSO details.

        if !SiteSetting.enable_sso or !api_key_valid?
          render nothing: true, status: 404
          return
        end

        sso = FanzySingleSignOn.parse(request.query_string)
        # user = sso.lookup_or_create_user
        if user = sso.lookup_or_create_user
          log_on_user user
        end

        render_serialized user, UserSerializer

      end

      # This is odd, but it seems that in Rails `render json: obj` is about
      # 20% slower than calling MultiJSON.dump ourselves. I'm not sure why
      # Rails doesn't call MultiJson.dump when you pass it json: obj but
      # it seems we don't need whatever Rails is doing.
      def render_serialized(obj, serializer, opts={})
        render_json_dump(serialize_data(obj, serializer, opts))
      end

      def render_json_dump(obj)
        render json: MultiJson.dump(obj)
      end

      def guardian
        @guardian ||= Guardian.new(current_user)
      end

      def serialize_data(obj, serializer, opts={})
        # If it's an array, apply the serializer as an each_serializer to the elements
        serializer_opts = {scope: guardian}.merge!(opts)
        if obj.respond_to?(:to_ary)
          serializer_opts[:each_serializer] = serializer
          ActiveModel::ArraySerializer.new(obj.to_ary, serializer_opts).as_json
        else
          serializer.new(obj, serializer_opts).as_json
        end
      end
      def api_key_valid?
        request["api_key"] && ApiKey.where(key: request["api_key"]).exists?
      end
    end

    ApiSso::Engine.routes.draw do
      get 'register_user' => 'api_sso#register_user'
    end

    Discourse::Application.routes.append do
      mount ::ApiSso::Engine, at: '/api_sso_login'
    end


    class FanzySingleSignOn < DiscourseSingleSignOn


      def self.parse(payload)
        sso = new
        parsed = Rack::Utils.parse_query payload

        # decoded = Base64.decode64(parsed["sso"])
        # decoded_hash = Rack::Utils.parse_query(decoded)

        ACCESSORS.each do |k|
          val = parsed[k.to_s]
          val = val.to_i if FIXNUMS.include? k
          sso.send("#{k}=", val)
        end

        # decoded_hash.each do |k,v|
        #   # 1234567
        #   # custom.
        #   #
        #   if k[0..6] == "custom."
        #     field = k[7..-1]
        #     sso.custom_fields[field] = v
        #   end
        # end

        sso
      end
    end
  end
end