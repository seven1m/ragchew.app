class Fetcher
  class Error < StandardError; end
  class NotFoundError < Error; end

  def initialize(host)
    @host = host
  end

  # in order to get more precise start/stop times for closed nets...
  #
  # GetPastNets.php
  #
  #
  # in order to fetch Net URLS...
  #
  # GetServerInfo.pl
  # (note ClubInfoListURL)
  #
  # fetch [ClubInfoListURL] from above
  # (get cli URLs from this file)
  #
  # fetch all cli files from above list
  # - note AboutURL and LogoURL
  # - note [Nets] patterns that match net names
  # - maybe note [NetList] names of specific nets
  #

  def get(endpoint, params = {})
    params_string = params.map { |k, v| "#{k}=#{v}" }.join('&')
    uri = URI("http://#{@host}/cgi-bin/NetLogger/#{endpoint}?#{params_string}")
    puts "GET #{uri}"
    html = Net::HTTP.get(uri).force_encoding('ISO-8859-1')
    raise NotFoundError, $1 if html =~ /\*error - (.*?)\*/m

    # to debug the raw server HTML...
    # ENV['DEBUG_HTML'] = true
    # NetInfo.new(name: 'foo').send(:fetch_raw, force_full: true)
    puts html if ENV['DEBUG_HTML']

    {}.tap do |result|
      html.scan(/<!--(.*?)-->(.*?)<!--.*?-->/m).each do |section, data|
        data.gsub!(/:~:/, '') # line-continuation ??
        result[section.strip] = data.split(/~|\n/).map { |line| line.split('|') }
      end
    end
  end

  def post(endpoint, params)
    uri = URI("http://#{@host}/cgi-bin/NetLogger/#{endpoint}")
    puts "POST #{uri}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form(params)

    # Having any user-agent header causes the netlogger server to drop the message :-(
    request['user-agent'] = nil

    response = http.request(request)

    raise Error, response.body unless response.is_a?(Net::HTTPOK)
    raise Error, $1 if response.body =~ /\*error - (.*?)\*/m

    response.body
  end
end
