Gem::Specification.new do |s|
  s.name        = 'bitso-apiv3'
  s.version     = '0.0.0'
  s.date        = '2019-12-28'
  s.summary     = "Bitso Wrapper!"
  s.description = "A simple wrapper for Bitso's APIv3"
  s.authors     = ["Daniel Vogel"]
  s.email       = 'vogel@bitso.com'
  s.files       = [
                  "lib/bitso/apiv3.rb",
                  "lib/bitso/apiv3/adapters/net_http.rb",
                  "lib/bitso/apiv3/ca-bitso.crt",
                  "lib/bitso/apiv3/client.rb",
                  "lib/bitso/apiv3/api_client.rb",
                  "lib/bitso/apiv3/api_object.rb",
                  "lib/bitso/apiv3/api_response.rb"
                  
                ]
  s.homepage    =
    'https://bitso.com/api_info'
  s.license       = 'MIT'
end
