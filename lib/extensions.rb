class String
  def present?
    strip.size > 0
  end

  def presence
    present? ? self : nil
  end
end

class NilClass
  def present?
    false
  end

  def presence
    nil
  end
end
