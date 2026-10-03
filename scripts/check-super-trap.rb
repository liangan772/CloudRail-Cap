#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Regression guard for the worst bug this plugin has carried.
#
# The tempting way to gate a core controller action is:
#
#   add_to_class(:users_controller, :create) do
#     ...
#     super()
#   end
#
# That cannot work, and it fails quietly enough to be misread as "the plugin is
# not enabled", because it depends on the name `add_to_class` invents for the
# block. Part 1 reproduces the failure with a verbatim copy of Discourse's
# implementation. Part 2 proves the pattern actually shipped - `reloadable_patch`
# plus a concern that adds a `before_action` - registers correctly. Part 3 proves
# an unverified submission is rejected rather than waved through.
#
# Run:  ruby scripts/check-super-trap.rb
# Exit: 0 = pass, 1 = fail.

# ---------------------------------------------------------------------------
# Minimal stand-in for ActiveSupport::Concern: enough to exercise our modules
# without booting Rails.
# ---------------------------------------------------------------------------
module ActiveSupport
  module Concern
    def self.extended(base)
      base.instance_variable_set(:@_concern_deps, [])
      base.instance_variable_set(:@_concern_block, nil)

      base.define_singleton_method(:included) do |arg = nil, &blk|
        if blk
          base.instance_variable_set(:@_concern_block, blk)
          base
        else
          base.instance_variable_get(:@_concern_deps).each { |dep| arg.include(dep) }
          super(arg)
          hook = base.instance_variable_get(:@_concern_block)
          arg.class_eval(&hook) if hook
          base
        end
      end

      base.define_singleton_method(:include) do |mod|
        if mod.instance_variable_defined?(:@_concern_deps)
          base.instance_variable_get(:@_concern_deps) << mod
          base
        else
          super(mod)
        end
      end
    end
  end
end

failures = []

# ---------------------------------------------------------------------------
# PART 1 - the trap, using Discourse's exact add_to_class implementation
# ---------------------------------------------------------------------------
class FakeApplicationController; end

class FakeUsersController < FakeApplicationController
  def create
    :created
  end
end

# Verbatim from lib/plugin/instance.rb
def add_to_class(klass, attr, &block)
  hidden_method_name = :"#{attr}_without_enable_check"
  klass.public_send(:define_method, hidden_method_name, &block)

  klass.public_send(:define_method, attr) do |*args, **kwargs|
    public_send(hidden_method_name, *args, **kwargs) if true # plugin.enabled?
  end
end

add_to_class(FakeUsersController, :create) { super() }
begin
  FakeUsersController.new.create
  failures << "super() did NOT raise - this test's assumption is stale"
rescue NoMethodError => e
  puts "  super()    -> NoMethodError: #{e.message.lines.first.strip}"
rescue StandardError => e
  failures << "super() raised #{e.class}, expected NoMethodError: #{e.message}"
end

class FakeUsersController2 < FakeApplicationController
  def create
    :created
  end
end
add_to_class(FakeUsersController2, :create) { super }
begin
  FakeUsersController2.new.create
  failures << "bare super did NOT raise - this test's assumption is stale"
rescue RuntimeError => e
  puts "  bare super -> RuntimeError: #{e.message.lines.first.strip}"
rescue StandardError => e
  failures << "bare super raised #{e.class}, expected RuntimeError: #{e.message}"
end

puts "  => add_to_class cannot wrap an existing action. Confirmed.\n\n"

# ---------------------------------------------------------------------------
# PART 2 - the shipped pattern registers a before_action on both controllers
# ---------------------------------------------------------------------------
class FakeTargetController
  def self.before_action(name, opts = {})
    (@registered ||= []) << [name, opts]
  end

  def self.registered_before_actions
    @registered || []
  end
end

# Stand-ins for the Discourse constants the patches touch at call time only.
Object.const_set(:SiteSetting, Module.new) unless defined?(SiteSetting)
SiteSetting.define_singleton_method(:cap_verification_enabled) { true }
SiteSetting.define_singleton_method(:cap_verification_protect_signup) { true }
SiteSetting.define_singleton_method(:cap_verification_protect_login) { true }

module I18n
  def self.t(key, *_args)
    "i18n:#{key}"
  end
end

class RateLimiter
  class LimitExceeded < StandardError; end
end

module DiscourseCap
  module Verify
    class Failure < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    # Same contract as the real thing: an unsolved challenge raises.
    class << self
      def enforce_session!(session:, remote_ip:, context:, actor: nil)
        record = session.delete(:cap_verification_verified)
        raise Failure.new(:missing_token) if record.nil? || record.respond_to?(:empty?) && record.empty?

        true
      end
    end
  end
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "discourse_cap/controller_patches"

class UserCtrl < FakeTargetController
  include DiscourseCap::UsersControllerPatch

  attr_reader :rendered

  def session
    @session ||= {}
  end

  def request
    @request ||= Struct.new(:remote_ip).new("203.0.113.1")
  end

  def current_user
    nil
  end

  def render_json_error(message, opts = {})
    @rendered = [message, opts]
  end
end

class SessionCtrl < FakeTargetController
  include DiscourseCap::SessionControllerPatch
end

expected = [[:check_cap_verification, { only: [:create] }]]

[[UserCtrl, "UsersController"], [SessionCtrl, "SessionController"]].each do |klass, label|
  actual = klass.registered_before_actions
  if actual == expected
    puts "  #{label}: before_action #{actual.inspect}"
  else
    failures << "#{label}: expected #{expected.inspect}, got #{actual.inspect}"
  end

  %i[check_cap_verification cap_verification_failure reject_unverified_cap].each do |m|
    failures << "#{label}: #{m} is not available to instances" unless klass.private_method_defined?(m)
  end
end

# ---------------------------------------------------------------------------
# PART 3 - fail closed: no solved challenge means 403, never a pass-through
# ---------------------------------------------------------------------------
probe = UserCtrl.new
probe.send(:check_cap_verification)

if probe.rendered.nil?
  failures << "an unverified signup was NOT rejected - enforcement is not wired up"
elsif probe.rendered[1][:status] != 403
  failures << "unverified signup rejected with #{probe.rendered[1].inspect}, expected 403"
else
  puts "  unverified signup -> #{probe.rendered[0]} (HTTP #{probe.rendered[1][:status]})"
end

puts
if failures.empty?
  puts "OK: all checks passed"
  exit 0
else
  puts "FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
