module Tables
  class Server < ActiveRecord::Base
    has_many :nets, dependent: :destroy

    scope :is_public, -> { where(is_public: true) }

    def self.by_host
      all.each_with_object({}) do |server, hash|
        hash[server.host] = server
      end
    end
  end
end
