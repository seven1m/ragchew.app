module Tables
  class Club < ActiveRecord::Base
    has_many :nets, dependent: :nullify
    has_many :closed_nets, dependent: :nullify

    serialize :net_patterns, JSON
    serialize :additional_net_patterns, JSON
    serialize :net_list, JSON

    def best_name
      full_name.presence || name
    end

    # returns an array of hashes, like this:
    #
    #     [
    #       { name: 'YL*' },
    #       { name: 'YL System 15m Session', frequency: '21.373' },
    #       ...
    #     ]
    #
    def all_net_conditions
      net_pattern_conditions +
        additional_net_pattern_conditions +
        net_list_conditions
    end

    private

    def net_pattern_conditions
      strings_to_conditions(net_patterns)
    end

    def additional_net_pattern_conditions
      strings_to_conditions(additional_net_patterns)
    end

    def strings_to_conditions(strings)
      if strings.is_a?(Array)
        strings.map do |name|
          if name.is_a?(String)
            { name: }
          end
        end.compact
      else
        []
      end
    end

    def net_list_conditions
      if net_list.is_a?(Array)
        net_list.map do |net|
          if net.is_a?(Hash)
            if net['name'].is_a?(String)
              {
                name: net['name'],
                frequency: net['frequency'],
              }
            end
          end
        end.compact
      else
        []
      end
    end
  end
end
