class GridSquare
  class Error < StandardError; end
  class BadGridSquareString < Error; end

  def initialize(string, error: false)
    if string.to_s.strip =~ /\A[A-R][A-R][0-9][0-9]($|[a-x][a-x])/i
      @string = $~.to_s
    elsif error
      raise BadGridSquareString
    end
  end

  def to_a
    return nil unless @string

    [latitude, longitude]
  end

  def longitude
    return nil unless @string

    field = (20 * (@string[0].upcase.ord - 'A'.ord)) - 180
    square = 2 * @string[2].to_i

    if @string[4]
      subsquare = 5 * (@string[4].downcase.ord - 'a'.ord) / 60.0
      # Center of 6-character subsquare (2.5 arcminutes wide)
      center_offset = 2.5 / 60.0
    else
      subsquare = 0
      # Center of 4-character square (2 degrees wide)
      center_offset = 1.0
    end

    field + square + subsquare + center_offset
  end

  def latitude
    return nil unless @string

    field = (10 * (@string[1].upcase.ord - 'A'.ord)) - 90
    square = @string[3].to_i

    if @string[5]
      subsquare = 2.5 * (@string[5].downcase.ord - 'a'.ord) / 60.0
      # Center of 6-character subsquare (2.5 arcminutes tall)
      center_offset = 1.25 / 60.0
    else
      subsquare = 0
      # Center of 4-character square (1 degree tall)
      center_offset = 0.5
    end

    field + square + subsquare + center_offset
  end
end
