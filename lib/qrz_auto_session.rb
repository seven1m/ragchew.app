require_relative './qrz'

class QrzAutoSession
  USERNAME = ENV.fetch('QRZ_USERNAME')
  PASSWORD = ENV.fetch('QRZ_PASSWORD')

  def lookup(call_sign)
    service.lookup(call_sign)
  rescue Qrz::SessionTimeout
    Thread.current[:qrz_session] = nil
    service.lookup(call_sign)
  end

  private

  def service
    if (session = Thread.current[:qrz_session])
      Qrz.new(session:)
    else
      qrz = Qrz.login(username: USERNAME, password: PASSWORD)
      Thread.current[:qrz_session] = qrz.session
      qrz
    end
  end
end
