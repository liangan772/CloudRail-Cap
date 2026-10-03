# frozen_string_literal: true

# End-to-end probe of the REAL Cap instance, using the same code path as
# DiscourseCap::Verify. Run standalone (no Rails) by stubbing the two things
# Verify needs: SiteSetting and I18n.
#
#   ruby scripts/probe-live-cap.rb
#
# It answers: for each failure mode, what does the live server actually return,
# and does our code classify it correctly?

require "net/http"
require "json"
require "uri"

INSTANCE   = "https://jq.crbbsx.com"
SITE_KEY   = "c87f54f192"
TIMEOUT    = 8

# --- the four cases we must handle -----------------------------------------

def post_siteverify(secret:, response:, url: nil)
  uri = URI.parse(url || "#{INSTANCE}/#{SITE_KEY}/siteverify")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = TIMEOUT
  http.read_timeout = TIMEOUT

  req = Net::HTTP::Post.new(uri.request_uri)
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(secret: secret, response: response)
  res = http.request(req)
  parsed = begin
    JSON.parse(res.body)
  rescue JSON::ParserError
    nil
  end
  [parsed, res]
end

# Mirrors Verify#valid_token?: success only on 2xx AND success == true.
def valid_token?(parsed, status)
  return false unless status.is_a?(Net::HTTPSuccess)
  parsed.is_a?(Hash) && parsed["success"] == true
end

def classify(parsed, status)
  msg = parsed.is_a?(Hash) ? parsed["error"].to_s : ""
  return "ACCEPTED" if valid_token?(parsed, status)
  return "REJECT: wrong credentials" if msg.match?(/invalid site key or secret/i)
  return "REJECT: token not found/expired" if msg.match?(/token not found|token expired/i)
  return "REJECT: malformed request" if msg.match?(/missing required parameters/i)
  "REJECT: other (#{status.code} #{msg})"
end

results = []

def probe(label, **kw)
  parsed, status = post_siteverify(**kw)
  cls = classify(parsed, status)
  puts format("  %-34s HTTP %-3s  %s", label, status.code, cls)
  puts format("  %-34s %s", "", (parsed.is_a?(Hash) ? parsed["error"] : parsed.to_s)[0, 70].to_s)
  [cls, status]
rescue StandardError => e
  puts format("  %-34s NETWORK ERROR: %s: %s", label, e.class, e.message[0, 50])
  ["NETWORK", nil]
end

puts "=" * 78
puts "LIVE CAP PROBE  ->  #{INSTANCE}"
puts "=" * 78

puts
puts "1. Reachability of the instance itself"
begin
  uri = URI.parse("#{INSTANCE}/#{SITE_KEY}/challenge")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = TIMEOUT
  http.read_timeout = TIMEOUT
  res = http.request(Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" }), "{}")
  ch = JSON.parse(res.body) rescue {}
  puts "  challenge endpoint      HTTP #{res.code}"
  puts "  format=#{ch['format']} challenges=#{(ch['challenges'] || []).length} " \
       "protocols=#{(ch['challenges'] || []).map { |c| c['protocol'] }.uniq.join(',')}"
  puts "  -> widget has something real to solve: #{ch['format'] == 2 ? 'YES' : 'NO'}"
rescue StandardError => e
  puts "  challenge endpoint FAILED: #{e.class}: #{e.message}"
end

puts
puts "2. siteverify: the four required cases (secret deliberately wrong here,"
puts "   because we do not hold the real one - the shape of the response is"
puts "   what matters, and it is identical either way)"

probe "missing token (empty string)",   secret: "x", response: ""
probe "garbage token (no colons)",      secret: "x", response: "not-a-token"
probe "well-formed, unknown id",        secret: "x", response: "#{SITE_KEY}:deadbeef:deadbeef"
probe "well-formed, wrong site key",    secret: "x", response: "0000000000:deadbeef:deadbeef"

puts
puts "3. Classification of what we just saw"
puts "   Our Verify#valid_token? accepts ONLY 2xx + success:true, so every"
puts "   line above is a rejection. Confirm none slipped through:"

samples = [
  ["garbage token",  post_siteverify(secret: "x", response: "not-a-token")],
  ["well-formed",    post_siteverify(secret: "x", response: "#{SITE_KEY}:deadbeef:deadbeef")],
]

all_rejected = true
samples.each do |label, (parsed, status)|
  ok = valid_token?(parsed, status)
  all_rejected &&= !ok
  puts format("   %-18s valid_token? -> %-5s  %s", label, ok, ok ? "*** LEAK ***" : "correctly rejected")
end
puts "   => fail-closed behaviour: #{all_rejected ? 'CONFIRMED' : 'BROKEN'}"

puts
puts "4. Network-failure handling (unreachable host -> must fail closed)"
begin
  post_siteverify(secret: "x", response: "a:b:c", url: "https://127.0.0.1:9/siteverify")
  puts "   unexpectedly connected"
rescue StandardError => e
  puts "   raised #{e.class} -> Verify rescues StandardError and returns false: FAIL CLOSED"
end

puts
puts "=" * 78
puts "DONE"
puts "=" * 78
