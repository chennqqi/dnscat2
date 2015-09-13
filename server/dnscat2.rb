##
# dnscat2_server.rb
# Created March, 2013
# By Ron Bowes
#
# See: LICENSE.md
#
# Implements basically the full Dnscat2 protocol. Doesn't care about
# lower-level protocols.
##

$LOAD_PATH << File.dirname(__FILE__) # A hack to make this work on 1.8/1.9

require 'tunnel_drivers/driver_dns'
require 'tunnel_drivers/driver_tcp'

require 'libs/log'
require 'controller/controller'
require 'libs/settings'

# Option parsing
require 'trollop'

# version info
NAME = "dnscat2"
VERSION = "0.03"

window = SWindow.new(nil, true, { :prompt => "dnscat2> ", :name => "main" })

window.puts("Welcome to dnscat2! Some documentation may be out of date")
window.puts()

controller = Controller.new(window)

# Capture log messages during start up - after creating a command session, all
# messages go to it, instead
Log.logging(nil) do |msg|
  window.puts("(old-style logging) " + msg.to_s())
end

# Options
opts = Trollop::options do
  version(NAME + " v" + VERSION + " (server)")

  opt :version,   "Get the dnscat version",
    :type => :boolean, :default => false

  opt :dns,       "Start a DNS server",
    :type => :boolean, :default => true
  opt :dnshost,   "The DNS ip address to listen on",
    :type => :string,  :default => "0.0.0.0"
  opt :dnsport,   "The DNS port to listen on",
    :type => :integer, :default => 53
  opt :passthrough, "If set (not by default), unhandled requests are sent to a real (upstream) DNS server",
    :type => :boolean, :default => false

  opt :tcp,       "Start a TCP server",
    :type => :boolean, :default => true
  opt :tcphost,   "The TCP ip address to listen on",
    :type => :string,  :default => "0.0.0.0"
  opt :tcpport,    "The port to listen on",
    :type => :integer, :default => 4444

  opt :debug,     "Min debug level [info, warning, error, fatal]",
    :type => :string,  :default => "warning"

  opt :auto_command,   "Send this to each client that connects",
    :type => :string,  :default => ""
  opt :auto_attach,    "Automatically attach to new sessions",
    :type => :boolean, :default => false
  opt :packet_trace,   "Display incoming/outgoing dnscat packets",
    :type => :boolean,  :default => false
  opt :isn,            "Set the initial sequence number",
    :type => :integer,  :default => nil
end

# Note: This is no longer strictly required, but it gives the user better feedback if
# they use a bad debug level, so I'm keeping it
#window.puts("Setting debug level to: #{opts[:debug].upcase()}")
#if(!Log.set_min_level(opts[:debug].upcase()))
#   Trollop::die :debug, "level values are: #{Log::LEVELS}"
#end

if(opts[:dnsport] < 0 || opts[:dnsport] > 65535)
  Trollop::die :dnsport, "must be a valid port"
end

if(opts[:tcpport] < 0 || opts[:tcpport] > 65535)
  Trollop::die :dnsport, "must be a valid port"
end

DriverDNS.passthrough = opts[:passthrough]
# Make a copy of ARGV
domains = [].replace(ARGV)

if(domains.length > 0)
  puts("Handling requests for the following domain(s):")
  puts(domains.join(", "))

  puts()
  puts("Assuming you are the authority, you can run clients like this:")
  puts()
  domains.each do |domain|
    puts("./dnscat2 #{domain}")
  end

  window.puts()
  window.puts("You can also run a directly-connected client:")
else
  window.puts("It looks like you didn't give me any domains to recognize!")
  window.puts("That's cool, though, you can still use a direct connection.")
  window.puts("Try running this on your client:")
end

window.puts()
window.puts("./dnscat2 --dns server=<server>")
window.puts()
window.puts("Of course, you have to figure out <server> yourself! Clients will connect")
window.puts("directly on UDP port 53 (by default).")
window.puts()

begin
  Settings::GLOBAL.create("packet_trace", Settings::TYPE_BOOLEAN, opts[:packet_trace].to_s()) do |old_val, new_val|
    # We don't have any callbacks
  end

  Settings::GLOBAL.create("debug", Settings::TYPE_STRING, opts[:debug]) do |old_val, new_val|
    if(Log::LEVELS.index(new_val.upcase).nil?)
      raise(Settings::ValidationError, "Bad debug value; possible values for 'debug': " + Log::LEVELS.join(", "))
    end

    if(old_val.nil?)
      window.puts("Set debug level to #{new_val}")
    else
      window.puts("Changed debug from #{old_val} to #{new_val}")
    end

    Log.set_min_level(new_val)
  end

  Settings::GLOBAL.create("passthrough", Settings::TYPE_BOOLEAN, opts[:passthrough].to_s()) do |old_val, new_val|
    DriverDNS.passthrough = new_val
  end

  Settings::GLOBAL.create("auto_attach", Settings::TYPE_BOOLEAN, opts[:auto_attach].to_s()) do |old_val, new_val|
  end

  Settings::GLOBAL.create("auto_command", Settings::TYPE_BLANK_IS_NIL, opts[:auto_command]) do |value|
  end
rescue Settings::ValidationError => e
  window.puts("There was an error with one of your commandline arguments:")
  window.puts(e)
  window.puts()

  Trollop::die("Check your command-line arguments")
end

#if(opts[:isn])
#  settings.set("isn",          opts[:isn])
#end

driver = DriverDNS.new(opts[:dnshost], opts[:dnsport], domains, window)
driver.recv() do |data, max_length|
  controller.feed(data, max_length)
end

puts("driver.recv() returned")

SWindow.wait()
