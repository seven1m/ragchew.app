class Fetcher
  class Error < StandardError; end
  class NotFoundError < Error; end

  USER_AGENT = nil # must be removed or NetLogger servers will not respond properly :-(

  def initialize(host)
    @host = host
  end

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
    html = raw_get(endpoint, params)

    {}.tap do |result|
      html.scan(/<!--(.*?)-->(.*?)<!--.*?-->/m).each do |section, data|
        data.gsub!(/:~:/, '') # line-continuation ??
        result[section.strip] = data.split(/\|~|\n/).map { |line| line.split('|') }
      end
    end
  end

  def raw_get(endpoint, params = {})
    params_string = params.map { |k, v| "#{k}=#{CGI.escapeURIComponent(v.to_s)}" }.join('&')
    uri = URI("https://#{@host}/cgi-bin/NetLogger/#{endpoint}?#{params_string}")
    puts "GET #{uri}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Get.new(uri.request_uri)

    request['user-agent'] = USER_AGENT
    response = http.request(request)

    raise Error, response.body unless response.is_a?(Net::HTTPOK)
    raise NotFoundError, $1 if response.body =~ /\*error - (.*?)\*/m

    html = response.body.force_encoding('ISO-8859-1')

    # to debug the raw server HTML...
    # ENV['DEBUG_HTML'] = true
    # NetInfo.new(name: 'foo').send(:fetch_raw, force_full: true)
    puts html if ENV['DEBUG_HTML']

    html
  end

  def post(endpoint, params)
    uri = URI("https://#{@host}/cgi-bin/NetLogger/#{endpoint}")
    puts "POST #{uri} with params #{params.inspect}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form(params)

    request['user-agent'] = USER_AGENT
    response = http.request(request)

    raise Error, response.body unless response.is_a?(Net::HTTPOK)
    raise Error, $1 if response.body =~ /\*error - (.*?)\*/m

    response.body
  end
end
