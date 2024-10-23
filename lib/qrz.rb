require 'cgi'
require 'net/http'
require 'uri'

class Qrz
  AGENT = "https://ragchew.app"
  BASE_URL = "https://xmldata.qrz.com/xml/current/"

  class Error < StandardError; end
  class NotACallSign < Error; end
  class NotFound < Error; end
  class WrongUsernamePassword < Error; end
  class SessionTimeout < Error; end

  def initialize(session:)
    @session = session
  end

  attr_reader :session

  def lookup(call_sign)
    call_sign = call_sign.upcase.strip
    raise NotACallSign if call_sign !~ /\A[A-Z]+\d[A-Z]+\z/

    result = self.class.call(s: @session, callsign: call_sign)
    if result =~ /<Error>(.*?)<\/Error>/
      message = $1.strip
      case message
      when /^not found/i
        raise NotFound, message
      when /session timeout/i
        raise SessionTimeout, message
      else
        raise Error, message
      end
    else
      parse_result(result)
    end
  end

  def self.login(username:, password:)
    result = call(username:, password:)
    if result =~ /<Error>(.*?)<\/Error>/m
      message = $1.strip
      if message.downcase == 'username/password incorrect'
        raise WrongUsernamePassword, message
      else
        raise Error, message
      end
    elsif result =~ /<Key>([A-Fa-f0-9]+)<\/Key>/
      new(session: $1)
    else
      raise Error, "unknown error occurred: #{result}"
    end
  end

  def self.call(**params)
    params.merge!(agent: AGENT)
    params_string = params.map { |k, v| "#{k}=#{CGI.escapeURIComponent(v)}" }.join(';')
    url = "#{BASE_URL}?#{params_string}"
    puts "GET #{url.sub(/password=[^;]+/, 'password=***')}"
    Net::HTTP.get(URI(url))
  end

  private

  def parse_result(result)
    station = Nokogiri::XML(result).at_css('Callsign')
    call_sign = station&.at_css('call')&.content

    raise Error, "unknown error occurred: #{result}" unless call_sign

    {
      call_sign:,
      first_name: station.at_css('fname')&.content,
      last_name: station.at_css('name')&.content,
      image: station.at_css('image')&.content,
      grid_square: station.at_css('grid')&.content,
      street: station.at_css('addr1')&.content,
      city: station.at_css('addr2')&.content,
      state: station.at_css('state')&.content,
      zip: station.at_css('zip')&.content,
      county: station.at_css('county')&.content,
      country: station.at_css('country')&.content,
      dxcc: station.at_css('dxcc')&.content,
    }
  end
end
