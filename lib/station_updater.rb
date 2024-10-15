class StationUpdater
  class NotFound < StandardError; end

  def initialize(call_sign)
    @call_sign = call_sign.strip.upcase
  end

  def call
    @station = Tables::Station.find_by(call_sign: @call_sign)
    if @station && !@station.expired?
      if @station.not_found?
        raise NotFound, "#{@call_sign} not found on QRZ"
      else
        return @station
      end
    end

    qrz = QrzAutoSession.new
    begin
      info = qrz.lookup(@call_sign)
      @station = Tables::Station
        .find_or_initialize_by(call_sign: @call_sign)
        .extend_expiration
      @station.update!(info)
    rescue Qrz::NotFound
      Tables::Station.find_or_initialize_by(call_sign: @call_sign)
        .extend_expiration
        .update!(not_found: true)
      raise NotFound, "#{@call_sign} not found on QRZ"
    rescue Qrz::NotACallSign
      raise NotFound, "#{@call_sign} not a call sign"
    end

    @station
  end
end
