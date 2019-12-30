module Bitso
  module APIv3
    class APIClient
      def initialize(api_key = '', api_secret = '', options = {})
        @api_uri = URI.parse(options[:api_url] || "https://api.bitso.com")
        @api_key = api_key
        @api_secret = api_secret
        @default_orderbook = options[:orderbook] || "btc_mxn"
      end

      def available_books(params = {})
        out = nil
        get("/v3/available_books/", params) do |resp|
          out = response_collection(resp)
          yield(out, resp) if block_given?
        end
        out
      end

      def ticker(params = {})
        out = nil
        get("/v3/ticker/", params) do |resp|
          out = response_collection(resp)
          yield(out, resp) if block_given?
        end
        out
      end

      def orderbook(params = {})
        params[:book] = @default_orderbook if params[:book] == nil

        out = nil
        get("/v3/order_book/", params) do |resp|
          out = response_object(resp)
          yield(out, resp) if block_given?
        end
        out
      end

      def balance(params = {})
        out = nil
        get("/v3/balance/", params) do |resp|
          out = response_object(resp)
          yield(out, resp) if block_given?
        end
        out
      end

      def bid(amt, price, params = {})
        params[:book] ||= @default_orderbook
        params[:side] = "buy"
        params[:type] = "limit"
        params[:major] = amt
        params[:price] = price

        out = nil
        post("/v3/orders", params) do |resp|
          out = response_object(resp)
          yield(out, resp) if block_given?
        end
        out
      end
      alias_method :buy, :bid

      def ask(amt, price, params = {})
        params[:book] ||= @default_orderbook
        params[:side] = "sell"
        params[:type] = "limit"
        params[:major] = amt
        params[:price] = price

        out = nil
        post("/v3/orders", params) do |resp|
          out = response_object(resp)
          yield(out, resp) if block_given?
        end
        out
      end
      alias_method :sell, :ask


      def open_orders(params = {})
        out = nil
        get("/v3/open_orders/", params) do |resp|
          out = response_collection(resp)
          yield(out, resp) if block_given?
        end
        out
      end

      def cancel_order(order_ids)
        return if order_ids == nil || order_ids.length == 0
        out = nil
        orders = order_ids.join("-")
        delete("/v3/orders/#{orders}") do |resp|
          out = response_object(resp)
          yield(out, resp) if block_given?
        end
        out
      end

      private

      def response_collection(resp)
        out = resp.map { |item| APIObject.new(item) }
        out.instance_eval { @response = resp }
        add_metadata(out)
        out
      end

      def response_object(resp)
        out = APIObject.new(resp)
        out.instance_eval { @response = resp.response }
        add_metadata(out)
        out
      end

      def add_metadata(resp)
        resp.instance_eval do
          def response
            @response
          end

          def raw
            @response.raw
          end

          def response_headers
            @response.headers
          end

          def response_status
            @response.status
          end
        end
        resp
      end

      def get(path, params = {}, options = {})
        params[:limit] ||= 100 if options[:paginate] == true

        http_verb('GET', "#{path}?#{URI.encode_www_form(params)}") do |resp|
          out = resp.body
          out.instance_eval { @response = resp }
          add_metadata(out)

          yield(out)
        end
      end

      def post(path, params = {})
        http_verb('POST', path, params.to_json) do |resp|
          out = resp.body
          out.instance_eval { @response = resp }
          add_metadata(out)
          yield(out)
        end
      end

      def delete(path)
        http_verb('DELETE', path) do |resp|
          out = resp.body
          out.instance_eval { @response = resp }
          add_metadata(out)
          yield(out)
        end
      end

      def http_verb(_method, _path, _body)
        fail NotImplementedError
      end

      def self.whitelisted_certificates
        path = File.expand_path(File.join(File.dirname(__FILE__), 'ca-bitso.crt'))

        certs = [ [] ]
        File.readlines(path).each do |line|
          next if ["\n", "#"].include?(line[0])
          certs.last << line
          certs << [] if line == "-----END CERTIFICATE-----\n"
        end

        result = OpenSSL::X509::Store.new

        certs.each do |lines|
          next if lines.empty?
          cert = OpenSSL::X509::Certificate.new(lines.join)
          result.add_cert(cert)
        end

        result
      end

    end
  end
end
