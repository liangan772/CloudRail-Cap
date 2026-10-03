# frozen_string_literal: true

RSpec.describe DiscourseCap::Verify do
  before do
    SiteSetting.cap_verification_enabled = true
    SiteSetting.cap_verification_instance_url = "https://cap.example.com"
    SiteSetting.cap_verification_site_key = "sk_test"
    SiteSetting.cap_verification_secret_key = "secret_test"
    SiteSetting.cap_verification_protect_signup = true
    SiteSetting.cap_verification_skip_for_staff = true
    SiteSetting.cap_verification_min_trust_level = 0
  end

  # A stand-in for the Rails session: only [], []= and delete are used.
  let(:session) { {} }

  def stub_siteverify(success:)
    stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_return(
      status: 200,
      body: { success: success }.to_json,
      headers: {
        "Content-Type" => "application/json",
      },
    )
  end

  describe ".redeem!" do
    it "records the verification in the session when Cap accepts the token" do
      stub_siteverify(success: true)

      expect(
        described_class.redeem!(
          token: "good-token",
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        ),
      ).to eq(true)

      expect(session[described_class::SESSION_KEY]).to include(
        "context" => "signup",
      )
    end

    it "raises invalid_token when the Cap server rejects it" do
      stub_siteverify(success: false)

      expect {
        described_class.redeem!(
          token: "bad-token",
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:invalid_token)
      }

      expect(session).to be_empty
    end

    it "raises missing_token when no token is submitted" do
      expect {
        described_class.redeem!(
          token: nil,
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:missing_token)
      }
    end

    it "raises token_too_long for an absurdly long token" do
      expect {
        described_class.redeem!(
          token: "x" * 4097,
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:token_too_long)
      }
    end

    it "raises not_configured when credentials are missing" do
      SiteSetting.cap_verification_secret_key = ""

      expect {
        described_class.redeem!(
          token: "good-token",
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:not_configured)
      }
    end
  end

  describe ".enforce_session!" do
    it "passes once the challenge has been solved" do
      stub_siteverify(success: true)
      described_class.redeem!(
        token: "good-token",
        session: session,
        remote_ip: "1.2.3.4",
        context: "signup",
      )

      expect(
        described_class.enforce_session!(
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        ),
      ).to eq(true)
    end

    it "consumes the flag, so one solved challenge cannot be replayed" do
      stub_siteverify(success: true)
      described_class.redeem!(
        token: "good-token",
        session: session,
        remote_ip: "1.2.3.4",
        context: "signup",
      )

      described_class.enforce_session!(
        session: session,
        remote_ip: "1.2.3.4",
        context: "signup",
      )

      expect {
        described_class.enforce_session!(
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:missing_token)
      }
    end

    it "raises missing_token when nothing was solved" do
      expect {
        described_class.enforce_session!(
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:missing_token)
      }
    end

    it "raises invalid_token once the verification has expired" do
      session[described_class::SESSION_KEY] = {
        "at" => (Time.zone.now - 1.hour).to_i,
        "context" => "signup",
      }

      expect {
        described_class.enforce_session!(
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:invalid_token)
      }
    end

    it "is a no-op when the plugin is disabled" do
      SiteSetting.cap_verification_enabled = false

      expect(
        described_class.enforce_session!(
          session: session,
          remote_ip: "1.2.3.4",
          context: "signup",
        ),
      ).to eq(true)
    end

    it "exempts staff" do
      staff = Fabricate(:admin)

      expect(
        described_class.enforce_session!(
          session: session,
          remote_ip: "1.2.3.4",
          context: "login",
          actor: staff,
        ),
      ).to eq(true)
    end

    it "exempts users at or above the configured trust level" do
      SiteSetting.cap_verification_min_trust_level = 2
      user = Fabricate(:user, trust_level: TrustLevel[2])

      expect(
        described_class.enforce_session!(
          session: session,
          remote_ip: "1.2.3.4",
          context: "login",
          actor: user,
        ),
      ).to eq(true)
    end
  end
end
