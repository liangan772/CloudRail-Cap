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

  describe ".valid_token?" do
    # Tokens are single-use, so a non-2xx must never be read as success. These
    # are the cases that decide whether a forged submission can get through.
    it "is true only on a 2xx response with success: true" do
      stub_siteverify(success: true)
      expect(described_class.valid_token?("a:b:c")).to eq(true)
    end

    it "is false when the server rejects the credentials" do
      stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_return(
        status: 403,
        body: { success: false, error: "Invalid site key or secret" }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )

      expect(described_class.valid_token?("a:b:c")).to eq(false)
    end

    it "is false when the token is unknown or already redeemed" do
      stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_return(
        status: 404,
        body: { success: false, error: "Token not found" }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )

      expect(described_class.valid_token?("a:b:c")).to eq(false)
    end

    it "fails closed when the Cap server cannot be reached" do
      stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_timeout
      expect(described_class.valid_token?("a:b:c")).to eq(false)
    end

    it "fails closed when the response body is not JSON" do
      stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_return(
        status: 200,
        body: "<html>502 Bad Gateway</html>",
        headers: {
          "Content-Type" => "text/html",
        },
      )

      expect(described_class.valid_token?("a:b:c")).to eq(false)
    end
  end

  describe ".test_connection" do
    # The probe token must contain exactly two colons. Cap rejects anything
    # else with HTTP 400 "Missing required parameters" *before* it looks at the
    # secret, so a malformed probe makes a correctly configured site report a
    # failure. This is a regression guard for exactly that bug.
    it "sends a token shaped the way Cap requires" do
      expect(described_class.probe_token.split(":").length).to eq(3)
    end

    def stub_probe(status:, body:)
      stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_return(
        status: status,
        body: body.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )
    end

    it "reports success when Cap accepts the credentials but not the token" do
      # This is what a healthy server returns for a made-up token: the secret
      # verified, then the token lookup missed. It is the success case.
      stub_probe(status: 404, body: { success: false, error: "Token not found" })

      expect(described_class.test_connection).to include(success: true)
    end

    it "reports a credentials problem when the secret is rejected" do
      stub_probe(status: 403, body: { success: false, error: "Invalid site key or secret" })

      result = described_class.test_connection

      expect(result[:success]).to eq(false)
      # The message comes from the locale file, so assert it is present rather
      # than matching prose that differs between en and zh_CN.
      expect(result[:error]).to be_present
      expect(result[:error]).to eq(I18n.t("cap_verification.admin.bad_credentials"))
    end

    it "fails closed when the Cap server is unreachable" do
      stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_raise(
        Errno::ECONNREFUSED,
      )

      expect(described_class.test_connection[:success]).to eq(false)
    end

    it "fails closed when the Cap server times out" do
      stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_timeout

      expect(described_class.test_connection[:success]).to eq(false)
    end

    it "refuses to probe when the credentials are incomplete" do
      SiteSetting.cap_verification_secret_key = ""

      expect(described_class.test_connection[:success]).to eq(false)
    end
  end
end
