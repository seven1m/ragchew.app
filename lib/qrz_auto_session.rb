require_relative './qrz'

class QrzAutoSession
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
      qrz = Qrz.login(username:, password:)
      Thread.current[:qrz_session] = qrz.session
      qrz
    end
  end

  def username
    ENV.fetch('QRZ_USERNAME')
  end

  def password
    ENV.fetch('QRZ_PASSWORD')
  end
end
