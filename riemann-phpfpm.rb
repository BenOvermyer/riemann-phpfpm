#!/usr/bin/env ruby

require 'riemann/client'
require 'typhoeus'
require 'json'

class RiemannPhpfpmCollector
  def initialize()
    configfile = File.open( "config.json", "r" )
    @opts = JSON.parse( configfile.read )
    @client = Riemann::Client.new host: @opts[ 'hostname' ], port: @opts[ 'port' ], timeout: @opts[ 'timeout' ]
  end

  def state( key, value )
    # @TODO Should define real states based on thresholds here
    return 'ok'
  end

  def report_metric( poolname, key, value )
    tags = @opts[ 'tags' ].split( "," )
    service = "php-fpm " + poolname + " " + key

    report( {
      :service => service,
      :metric => value.to_i,
      :state => state( key, value ),
      :tags => tags
    } )
  end

  def report(event)
    puts event
    @client.tcp << event
  end

  def tick
    response = nil
    tags = @opts[ 'tags' ].split( "," )

    for pool in @opts[ 'pools' ]
      url = "http://" + pool[ 'watchhost' ] + "/" + pool[ 'watchroute' ] + "?json"
      service = "php-fpm " + pool[ 'name' ] + " health"

      begin
        response = Typhoeus.get( url )
      rescue => e
        report( {
          :service => service,
          :state => 'critical',
          :description => "Connection error: #{e.class} - #{e.message}",
          :tags => tags
        } )
      end

      return if response.nil?

      report( {
        :service => service,
        :state => 'ok',
        :description => 'php-fpm status connection ok',
        :tags => tags
      } )

      metrics = JSON.parse( response.body )

      metrics.each do |key, value|
        report_metric( pool[ 'name' ], key, value ) unless [ "pool", "process manager", "start time" ].include?( key )
      end

    end
  end

  def run
    t0 = Time.now
    loop do
      begin
        tick
      rescue => e
        $stderr.puts "#{e.class} #{e}\n#{e.backtrace.join "\n"}"
      end

      sleep( 5 - ( ( Time.now - t0 ) % 5 ) )
    end
  end
end

RiemannPhpfpmCollector.new.run
