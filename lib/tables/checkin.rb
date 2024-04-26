module Tables
  class Checkin < ActiveRecord::Base
    belongs_to :net

    scope :not_blank, -> {
      where(
        "(call_sign IS NOT NULL and TRIM(call_sign) != '') OR " \
          "(remarks IS NOT NULL and TRIM(remarks) != '')"
      )
    }
  end
end
