$stdout.sync = true
$stderr.sync = true

begin
  require_relative './app'
  puts "BUILD OK"
rescue Exception => e
  STDERR.puts "BUILD FAILED: #{e.class} - #{e.message}"
  STDERR.puts e.backtrace.join("\n")
  exit(1)
end
