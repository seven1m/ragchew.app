require 'cgi'
require 'net/http'
require 'uri'

class Qrz
  AGENT = "https://ragchew.app"
  BASE_URL = "https://xmldata.qrz.com/xml/current/"

  class Error < StandardError; end
  class NotFound < Error; end
  class WrongUsernamePassword < Error; end

  def initialize(session:)
    @session = session
  end

  attr_reader :session

  def lookup(call_sign)
    result = self.class.call(s: @session, callsign: call_sign)
    if result =~ /<Error>(.*?)<\/Error>/
      message = $1.strip
      if message =~ /^not found/i
        raise NotFound, message
      else
        raise Error, message
      end
    elsif result =~ /<call>(.*?)<\/call>/i
      actual_call_sign = $1.strip
      first_name = (result.match(/<fname>(.*?)<\/fname>/) || [])[1]
      last_name = (result.match(/<name>(.*?)<\/name>/) || [])[1]
      image = (result.match(/<image>(.*?)<\/image>/) || [])[1]
      {
        call_sign: actual_call_sign,
        first_name:,
        last_name:,
        image:
      }
    else
      raise Error, "unknown error occurred: #{result}"
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
    params_string = params.map { |k, v| "#{k}=#{CGI.escape(v)}" }.join(';')
    Net::HTTP.get(URI("#{BASE_URL}?#{params_string}"))
  end
end
