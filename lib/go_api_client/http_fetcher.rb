require 'net/http'
require 'net/https'

module GoApiClient
  class HttpFetcher

    class ConnectionError <StandardError
    end

    class HttpError < ConnectionError
      attr_reader :http_code
      def initialize(msg, http_code)
        super(msg)
        @http_code = http_code
      end
    end

    NET_HTTP_EXCEPTIONS = [
      EOFError,
      Errno::ECONNABORTED,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::ECONNRESET, EOFError,
      Errno::EINVAL,
      Errno::ETIMEDOUT,
      Net::HTTPBadResponse,
      Net::HTTPClientError,
      Net::HTTPError,
      Net::HTTPFatalError,
      Net::HTTPHeaderSyntaxError,
      Net::HTTPRetriableError,
      Net::HTTPServerException,
      Net::ProtocolError,
      SocketError,
      Timeout::Error,
    ]

    NET_HTTP_EXCEPTIONS << OpenSSL::SSL::SSLError if defined?(OpenSSL)

    attr_accessor :response

    def initialize(options={})
      @username = options[:username]
      @password = options[:password]
    end

    %w(get post).each do |meth|
      class_eval <<-RUBY_EVAL, __FILE__, __LINE__ + 1
      def #{meth}!(url, options={})
        response_body = #{meth}(url, options)
        if failure?
          message = "Could not fetch url \#{url}."
          GoApiClient.logger.error("\#{message} The response returned status \#{status} with body `\#{response_body}'")
          raise HttpError.new(message, status)
        end
        return response_body
      rescue *NET_HTTP_EXCEPTIONS => e
        message = "Could not connect to url \#{url}."
        GoApiClient.logger.error("\#{message}. The error was \#{e.message}")
        GoApiClient.logger.error(e.backtrace.collect {|l| "    \#{l}"}.join("\n"))
        raise ConnectionError.new(e)
      end
      RUBY_EVAL
    end

    def status
      @response.code.to_i
    end

    def success?
      (200..299).include?(status)
    end

    def failure?
      !success?
    end

    private


      def get(url, options={})
        uri = URI.parse(url)

        password = options[:password] || uri.password || @password
        username = options[:username] || uri.user     || @username
        params   = options[:params]   || {}

        uri.query = URI.encode_www_form(params) if params.any?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        @response = http.start do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          req.basic_auth(username, password) if username || password
          http.request(req)
        end
        return @response.body
      end

      def post(url, options={})
        uri = URI.parse(url)

        password = options[:password] || uri.password || @password
        username = options[:username] || uri.user     || @username
        params   = options[:params]   || {}
        headers  = options[:headers]  || {}

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        req = Net::HTTP::Post.new(uri.request_uri)

        headers.each do |header_name, value|
          req[header_name] = value
        end

        req.basic_auth(username, password) if username || password

        req.set_form_data(params)
        @response = http.request(req)
        return @response.body
      end
  end
end
