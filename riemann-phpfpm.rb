#!/usr/bin/env ruby

require 'riemann/client'
require 'config.rb'

class RiemannPhpfpmCollector
  def initialize(opts)
    @client = Riemann::Client.new host: opts[ :hostname ], port: opts[ :port ], timeout: opts[ :timeout ]
  end

  def state( key, value )
    # @TODO Should define real states based on thresholds here
    return 'ok'
  end

  def report_metric( key, value )
    report( {
      :service => "php-fpm #{key}",
      :metric => value.to_i,
      :state => state( key, value ),
      :tags => [ 'php-fpm' ]
    } )
  end

  def report(event)
    @client << event
  end

  def tick
    response = nil
    begin
      curlresult = Curl.get( "http://" + opts[:watchhost] + "/" opts[:watchroute] + "?json" )
      response = curlresult.body_str
    rescue => e
      report( {
        :service => 'php-fpm health',
        :state => 'critical',
        :description => "Connection error: #{e.class} - #{e.message}"
      } )
    end

    return if response.nil?

    report( {
      :service => 'php-fpm health',
      :state => 'ok',
      :description => 'php-fpm status connection ok'
    } )

    metrics = JSON.parse( response )

    metrics.each do |key, value|
      report_metric( key, value ) unless [ "pool", "process manager", "start time" ].include?( key )
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

RiemannPhpfpmCollector.new(opts).run
