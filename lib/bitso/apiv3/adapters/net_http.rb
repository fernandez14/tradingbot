module Bitso
  module APIv3
    # Net-HTTP adapter
    class NetHTTPClient < APIClient
      def initialize(api_key = '', api_secret = '', options = {})
        super(api_key, api_secret, options)
        @conn = Net::HTTP.new(@api_uri.host, @api_uri.port)
        @conn.use_ssl = true if @api_uri.scheme == 'https'
        @conn.cert_store = self.class.whitelisted_certificates
        @conn.ssl_version = :SSLv23_client
        @last_nonce = nil
      end

      private

      def http_verb(method, path, body = nil)
        case method
        when 'GET' then req = Net::HTTP::Get.new(path)
        when 'POST' then req = Net::HTTP::Post.new(path)
        when 'DELETE' then req = Net::HTTP::Delete.new(path)
        else fail
        end

        req.body = body

        nonce = DateTime.now.strftime('%Q')
        nonce = @last_nonce + 1 if nonce <= @last_nonce
        @last_nonce = nonce
        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), @api_secret, "#{nonce}#{method}#{path}#{body}")
        auth_header = "Bitso #{@api_key}:#{nonce}:#{signature}"

        req['Content-Type'] = 'application/json'
        req['Authorization'] = auth_header

        resp = @conn.request(req)
        if resp.code == "200"
          begin
            out = JSON.parse(resp.body)
            if out["success"] == true
              yield(NetHTTPResponse.new(resp))
              return
            end
          rescue JSON::ParserError
          end
          fail BadRequestError, resp.body
        end
        case resp.code
        #when "200" then yield(NetHTTPResponse.new(resp))
        when "400" then fail BadRequestError, resp.body
        when "401" then fail NotAuthorizedError, resp.body
        when "403" then fail ForbiddenError, resp.body
        when "404" then fail NotFoundError, resp.body
        when "429" then fail RateLimitError, resp.body
        when "500" then fail InternalServerError, resp.body
        end
        resp.body
      end
    end

    # Net-Http response object
    class NetHTTPResponse < APIResponse
      def body
        JSON.parse(@response.body)["payload"]
      end

      def headers
        out = @response.to_hash.map do |key, val|
          [ key.upcase.gsub('_', '-'), val.count == 1 ? val.first : val ]
        end
        out.to_h
      end

      def status
        @response.code.to_i
      end
    end
  end
end
