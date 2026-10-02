# frozen_string_literal: true

# Rails 8+ REQUIRES the version bracket. `class Foo < ActiveRecord::Migration`
# raises "Directly inheriting from ActiveRecord::Migration is not supported" and
# aborts `rake db:migrate`, which fails the whole bootstrap.
#
# Match the number to the Rails release the target Discourse ships. Discourse
# main currently runs Rails 8.1, so this is [8.1]. If a site pins an older
# Discourse on Rails 8.0, change this to [8.0].
class CreateDiscourseCapVerificationLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :discourse_cap_verification_logs do |t|
      t.string :remote_ip, null: false
      t.string :context, null: false
      t.string :reason

      # VerificationLog is a plain ActiveRecord model, so it expects both
      # columns. A hand-rolled `created_at` with no `updated_at` breaks the
      # very first insert.
      t.timestamps
    end

    add_index :discourse_cap_verification_logs, :created_at
    add_index :discourse_cap_verification_logs, %i[remote_ip created_at]
  end
end
