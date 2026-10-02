# frozen_string_literal: true

class CreateDiscourseCapVerificationLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :discourse_cap_verification_logs do |t|
      t.string :remote_ip, null: false
      t.string :context, null: false
      t.string :reason
      t.datetime :created_at, null: false
    end

    add_index :discourse_cap_verification_logs, :created_at
    add_index :discourse_cap_verification_logs, %i[remote_ip created_at]
  end
end
