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

class Hash
  def symbolize_keys
    each_with_object({}) do |(key, value), hash|
      hash[key.to_sym] = value
    end
  end
end
