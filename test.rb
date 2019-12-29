#!/usr/bin/ruby

require 'bitso/apiv3'

class CurrencyLayer
  def initialize(api_key)
    @api_key = api_key
    @conn = Net::HTTP.new("apilayer.net", 443)
    @conn.use_ssl = true
  end

  def get_quote
    req = Net::HTTP::Get.new("/api/live?access_key=#{@api_key}&currencies=ARS&source=MXN")
    resp = @conn.request(req)
    begin
      j = JSON.parse(resp.body)
      if j["success"] == true
        return j["quotes"]["MXNARS"]
      end
    rescue JSON::ParserError
    end
    return nil
  end
end


# read -p "Enter Bitso API key: " -s BITSO_API_KEY && export BITSO_API_KEY && echo && read -p "Enter Bitso API secret: " -s BITSO_API_SECRET && export BITSO_API_SECRET && echo && read -p "Enter CL API key: " -s CL_API && export CL_API && echo
rest_api = Bitso::APIv3::Client.new(ENV["BITSO_API_KEY"], ENV["BITSO_API_SECRET"])
cl = CurrencyLayer.new(ENV["CL_API"])
quote = cl.get_quote
puts quote

#puts rest_api.available_books
#puts rest_api.available_books(:ws => "1")
#puts rest_api.ticker
#puts rest_api.orderbook
#puts rest_api.orderbook(:book => "eth_mxn").asks


