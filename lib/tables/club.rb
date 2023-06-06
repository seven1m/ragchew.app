module Tables
  class Club < ActiveRecord::Base
    has_many :nets
    has_many :closed_nets

    serialize :net_patterns, JSON
    serialize :additional_net_patterns, JSON
    serialize :net_list, JSON

    def best_name
      full_name.presence || name
    end

    def all_patterns
      net_patterns_as_strings +
        additional_net_patterns_as_strings +
        net_list_as_strings
    end

    private

    def net_patterns_as_strings
      if net_patterns.is_a?(Array)
        net_patterns.map { |n| n.is_a?(String) ? n : nil }.compact
      else
        []
      end
    end

    def additional_net_patterns_as_strings
      if additional_net_patterns.is_a?(Array)
        additional_net_patterns.map { |n| n.is_a?(String) ? n : nil }.compact
      else
        []
      end
    end

    def net_list_as_strings
      if net_list.is_a?(Array)
        net_list.map do |net|
          if net.is_a?(Hash)
            if net['name'].is_a?(String)
              net['name']
            end
          end
        end.compact
      else
        []
      end
    end
  end
end
