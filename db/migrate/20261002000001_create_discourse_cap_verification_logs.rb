# frozen_string_literal: true

# Discourse plugins declare migrations without pinning an ActiveRecord
# migration version. Pinning a version such as [7.0] makes the migration class
# resolve against a compatibility shim that is not guaranteed to exist in the
# Rails version a given Discourse release ships, which fails the whole
# `rake db:migrate` run at bootstrap.
class CreateDiscourseCapVerificationLogs < ActiveRecord::Migration
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
