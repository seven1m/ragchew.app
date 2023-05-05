class Fetcher
  class NotFoundError < StandardError; end

  def initialize(host)
    @host = host
  end

  def get(endpoint, params)
    params_string = params.map { |k, v| "#{k}=#{v}" }.join('&')
    html = Net::HTTP.get(URI("http://#{@host}/cgi-bin/NetLogger/#{endpoint}?#{params_string}"))
    raise NotFoundError, $1 if html =~ /\*error - (.*?)\*/m

    {}.tap do |result|
      html.scan(/<!--(.*?)-->(.*?)<!--.*?-->/m).each do |section, data|
        result[section.strip] = data.split(/~|\n/).map { |line| line.split('|') }
      end
    end
  end
end
