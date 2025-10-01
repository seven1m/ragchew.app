module BitFlags
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def bit_flag(name, bit)
      define_method("#{name}?") do
        flags & (1 << bit) != 0
      end

      define_method("#{name}=") do |value|
        if value
          self.flags |= (1 << bit)
        else
          self.flags &= ~(1 << bit)
        end
      end
    end
  end
end
