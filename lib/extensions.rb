class String
  def present?
    strip.size > 0
  end
end

class NilClass
  def present?
    false
  end
end
