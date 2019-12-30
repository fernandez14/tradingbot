#!/usr/bin/ruby

require 'bitso/apiv3'
require 'bigdecimal'

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
        return BigDecimal(j["quotes"]["MXNARS"], 6)
      end
    rescue JSON::ParserError
    end
    return nil
  end
end

def getBalances
  balance = $bitso.balance

  h = Hash.new
  balance["balances"].each do |b|
    h["ars"] = b if b["currency"] == "ars"
    h["btc"] = b if b["currency"] == "btc"
  end

  return h
end

def getBTCMXN
  ticker = $bitso.ticker
  ticker.each do |t|
    return BigDecimal(t["last"]) if t["book"] == "btc_mxn"
  end
  return nil
end

def calculateSpreads(balances, ars_mxn)
  mxn_btc = getBTCMXN
  ars_balance = BigDecimal(balances["ars"]["total"])
  btc_in_ars = BigDecimal(balances["btc"]["total"]).mult(mxn_btc, 8).mult(ars_mxn, 8)
  total_balance_in_ars = ars_balance.add(btc_in_ars, 8)
  btc_percentage = btc_in_ars.div(total_balance_in_ars, 8)
  puts "BTC is at #{btc_percentage.mult(BigDecimal("100"), 2).to_s("F")}%"
  puts "ARS is at #{BigDecimal("100").sub(btc_percentage.mult(BigDecimal("100"), 2), 2).to_s("F")}%"

  h = Hash.new
  h["bid_spread"] = $max_spread
  h["ask_spread"] = $max_spread
  m = ($min_spread-$max_spread)/BigDecimal("0.5")
  b = $min_spread-($min_spread-$max_spread)/BigDecimal("0.5")
  if (btc_percentage > BigDecimal("0.5"))
    puts "Reducing ask spread"
    h["ask_spread"] = m*btc_percentage+b
  elsif (btc_percentage < BigDecimal("0.5"))
    puts "Reducing bids spread"
    h["bid_spread"] = m*(BigDecimal("1")-btc_percentage)+b
  end
  puts "Setting bid spread to #{(h["bid_spread"]*BigDecimal("100")).to_s("F")} %"
  puts "Setting ask spread to #{(h["ask_spread"]*BigDecimal("100")).to_s("F")} %"
  return h
end

def getLimits
  books = $bitso.available_books
  h = Hash.new
  books.each do |b|
    return b if b["book"] == "btc_ars"
  end
end

$min_spread = BigDecimal("0.28")
$max_spread = BigDecimal("0.40")
$order_num_threshold = 10 # lower to make fewer orders with tighter, increase to spread orders and prices

# read -p "Enter Bitso API key: " -s BITSO_API_KEY && export BITSO_API_KEY && echo && read -p "Enter Bitso API secret: " -s BITSO_API_SECRET && export BITSO_API_SECRET && echo && read -p "Enter CL API key: " -s CL_API && export CL_API && echo
$bitso = Bitso::APIv3::Client.new(ENV["BITSO_API_KEY"], ENV["BITSO_API_SECRET"])
$cl = CurrencyLayer.new(ENV["CL_API"])

while true
  balances = getBalances
  ars_mxn = $cl.get_quote
  spreads = calculateSpreads(balances, ars_mxn)
  ob = $bitso.orderbook(:book => "btc_mxn")

  # Calculate min/max prices on bids and asks
  min_bid_price = (BigDecimal(ob.bids[$order_num_threshold]["price"])*ars_mxn*(BigDecimal("1")-spreads["bid_spread"]))*BigDecimal("0.99")
  max_bid_price = (BigDecimal(ob.bids[0]["price"])*ars_mxn*(BigDecimal("1")-spreads["bid_spread"]))*BigDecimal("1.01")
  puts "Bid Prices: #{min_bid_price.to_s("F")} - #{max_bid_price.to_s("F")}"
  min_ask_price = (BigDecimal(ob.asks[0]["price"])*ars_mxn*(BigDecimal("1")+spreads["ask_spread"]))*BigDecimal("0.99")
  max_ask_price = (BigDecimal(ob.asks[$order_num_threshold]["price"])*ars_mxn*(BigDecimal("1")+spreads["ask_spread"]))*BigDecimal("1.01")
  puts "Ask Prices: #{min_ask_price.to_s("F")} - #{max_ask_price.to_s("F")}"

  # Cancel open orders outside of the min/max prices
  open_orders = $bitso.open_orders(:limit => 100)
  puts "There are #{open_orders.length} open orders at this time"
  orders = []
  open_orders.each do |o|
    price = BigDecimal(o["price"])
    if o["side"] == "buy"
      orders.push(o["oid"]) if price < min_bid_price || price > max_bid_price
    else
      orders.push(o["oid"]) if price < min_ask_price || price > max_ask_price
    end
  end
  puts "Cancelling #{orders.length} orders that are out of the price range"
  $bitso.cancel_order(orders)

  balances = getBalances
  limits = getLimits

  btc_balance = BigDecimal(balances["btc"]["available"])
  if btc_balance >= BigDecimal(limits["minimum_amount"])
    placed = BigDecimal("0")
    total = BigDecimal("0")
    count = 0
    ob.asks.each do |a|
      break if count >= $order_num_threshold
      total += BigDecimal(a["amount"])
      count += 1
    end
    count = 0
    ob.asks.each do |a|
      break if count >= $order_num_threshold
      amount = (BigDecimal(a["amount"])*BigDecimal(a["amount"])/total).truncate(8)
      next if amount <= BigDecimal(limits["minimum_amount"])
      next if amount >= (btc_balance - placed)

      price = (BigDecimal(a["price"]) * ars_mxn * (BigDecimal("1") + spreads["ask_spread"])).truncate(2)

      puts "Adding order to sell #{amount.to_s("F")} BTC at #{price.to_s("F")} ARS"
      $bitso.ask(amount.to_s("F"), price.to_s("F"), :book => "btc_ars")
      placed += amount
      count += 1
    end
  end

  ars_balance = BigDecimal(balances["ars"]["available"])
  if ars_balance >= BigDecimal(limits["minimum_value"])
    placed = BigDecimal("0")
    total = BigDecimal("0")
    count = 0
    ob.bids.each do |b|
      break if count >= $order_num_threshold
      value = BigDecimal(b["amount"])*BigDecimal(b["price"])
      total += value
      count += 1
    end
    count = 0
    ob.bids.each do |b|
      break if count >= $order_num_threshold
      value = BigDecimal(b["amount"])*BigDecimal(b["price"])
      amount = (BigDecimal(b["amount"])*value/total).truncate(8)
      price = (BigDecimal(b["price"]) * ars_mxn * (BigDecimal("1") - spreads["bid_spread"])).truncate(2)
      value_of_new_order = amount * price

      next if value_of_new_order <= BigDecimal(limits["minimum_value"])
      next if value_of_new_order > (ars_balance - placed)
      next if amount <= BigDecimal(limits["minimum_amount"])

      puts "Adding order to buy #{amount.to_s("F")} BTC at #{price.to_s("F")} ARS"
      $bitso.bid(amount.to_s("F"), price.to_s("F"), :book => "btc_ars")
      placed += value_of_new_order
      count += 1
    end
  end

  sleep 10
end
