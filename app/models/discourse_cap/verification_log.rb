# frozen_string_literal: true

module DiscourseCap
  # Lightweight audit trail for failed verifications. Deliberately stores no
  # token material - only enough to spot an attack in progress.
  class VerificationLog < ::ActiveRecord::Base
    self.table_name = "discourse_cap_verification_logs"

    validates :remote_ip, presence: true
    validates :context, presence: true

    def self.recent_count(hours: 24)
      where("created_at > ?", hours.hours.ago).count
    end

    def self.prune!
      where("created_at < ?", 30.days.ago).delete_all
    end
  end
end
