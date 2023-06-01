module NetLike
  def show_circle?
    center_latitude && center_longitude && center_radius
  end

  def self.included(klass)
    klass.class_eval do
      scope :matching_patterns, ->(patterns) {
        t = arel_table
        likes = patterns.map do |pattern|
          pattern.gsub('%', "\\%").tr('*', '%')
        end
        where(t[:name].matches_any(likes))
      }
    end
  end
end
