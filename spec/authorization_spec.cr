require "./spec_helper"

private class AssertingTokenFactory
  include AMC::TokenFactory::Interface

  getter? called : Bool = false

  def initialize(
    @token : String,
    @subscribe : Array(String)? = [] of String,
    @publish : Array(String)? = [] of String,
    @additional_claims : Hash(String, String) = {} of String => String
  )
  end

  def create(subscribe : Array(String) | ::Nil = [] of String, publish : Array(String) | ::Nil = [] of String, additional_claims : Hash | ::Nil = nil) : String
    subscribe.should eq @subscribe
    publish.should eq @publish
    additional_claims.should eq @additional_claims

    @token
  ensure
    @called = true
  end
end

# @[ASPEC::TestCase::Focus]
struct AuthorizationTest < ASPEC::TestCase
  def test_jwt_lifetime : Nil
    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      "https://example.com/.well-known/mercure",
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: AMC::TokenFactory::JWT.new("looooooooooooongenoughtestsecret", jwt_lifetime: 4000)
    ) { "ID" })

    authorization = AMC::Authorization.new registry
    cookie = authorization.create_cookie HTTP::Request.new("GET", "https://example.com", headers: HTTP::Headers{"host" => "example.com"})

    payload, _ = JWT.decode(cookie.value, verify: false, validate: false)
    payload["exp"].as_i?.should be_a Int32
  end

  def test_set_cookie_zero_expiration : Nil
    token_factory = AssertingTokenFactory.new(
      "JWT",
      ["foo"],
      ["bar"],
      {"x-foo" => "baz"},
    )

    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      "https://example.com/.well-known/mercure",
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: token_factory
    ) { "ID" })

    request = HTTP::Request.new("GET", "https://example.com", headers: HTTP::Headers{"host" => "example.com"})
    response = HTTP::Server::Response.new IO::Memory.new

    authorization = AMC::Authorization.new registry, Time::Span.zero, :lax
    authorization.set_cookie request, response, ["foo"], ["bar"], {"x-foo" => "baz"}
    token_factory.called?.should be_true

    cookie = response.cookies.first
    cookie.max_age.should eq Time::Span.zero
    cookie.value.should_not be_empty
    cookie.samesite.try &.lax?.should be_true
  end

  def test_set_cookie_default_expiration : Nil
    token_factory = AssertingTokenFactory.new(
      "JWT",
      ["foo"],
      ["bar"],
      {"x-foo" => "baz"},
    )

    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      "https://example.com/.well-known/mercure",
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: token_factory
    ) { "ID" })

    request = HTTP::Request.new("GET", "https://example.com", headers: HTTP::Headers{"host" => "example.com"})
    response = HTTP::Server::Response.new IO::Memory.new

    authorization = AMC::Authorization.new registry, cookie_samesite: :lax
    authorization.set_cookie request, response, ["foo"], ["bar"], {"x-foo" => "baz"}
    token_factory.called?.should be_true

    cookie = response.cookies.first
    cookie.max_age.should eq 1.hour
    cookie.value.should_not be_nil
    cookie.samesite.try &.lax?.should be_true
  end

  def test_clear_cookie : Nil
    token_factory = AssertingTokenFactory.new("JWT")

    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      "https://example.com/.well-known/mercure",
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: token_factory
    ) { "ID" })

    request = HTTP::Request.new("GET", "https://example.com", headers: HTTP::Headers{"host" => "example.com"})
    response = HTTP::Server::Response.new IO::Memory.new

    authorization = AMC::Authorization.new registry
    authorization.clear_cookie request, response

    cookie = response.cookies.first
    cookie.value.should be_empty
    cookie.max_age.should eq 1.second
  end

  @[DataProvider("applicable_cookie_domains")]
  def test_applicable_cookie_domains(expected : String?, hub_url : String, request_url : String) : Nil
    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      hub_url,
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: AMC::TokenFactory::JWT.new("looooooooooooongenoughtestsecret", jwt_lifetime: 4000)
    ) { "ID" })

    uri = URI.parse request_url
    request = HTTP::Request.new("GET", uri.path, headers: HTTP::Headers{"host" => uri.hostname || ""})

    authorization = AMC::Authorization.new registry

    cookie = authorization.create_cookie request
    cookie.domain.should eq expected
  end

  def applicable_cookie_domains : Tuple
    {
      {".example.com", "https://foo.bar.baz.example.com", "https://foo.bar.baz.qux.example.com"},
      {".foo.bar.baz.example.com", "https://mercure.foo.bar.baz.example.com", "https://app.foo.bar.baz.example.com"},
      {"example.com", "https://demo.example.com", "https://example.com"},
      {".example.com", "https://mercure.example.com", "https://app.example.com"},
      {".example.com", "https://example.com/.well-known/mercure", "https://app.example.com"},
      {nil, "https://example.com/.well-known/mercure", "https://example.com"},
    }
  end

  @[DataProvider("nonapplicable_cookie_domains")]
  def test_nonapplicable_cookie_domains(hub_url : String, request_url : String) : Nil
    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      hub_url,
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: AMC::TokenFactory::JWT.new("looooooooooooongenoughtestsecret", jwt_lifetime: 4000)
    ) { "ID" })

    uri = URI.parse request_url
    request = HTTP::Request.new("GET", uri.path, headers: HTTP::Headers{"host" => uri.hostname || ""})

    authorization = AMC::Authorization.new registry

    expect_raises AMC::Exceptions::InvalidArgument, "Unable to create authorization cookie for a hub on the different second-level domain" do
      authorization.create_cookie request
    end
  end

  def nonapplicable_cookie_domains : Tuple
    {
      {"https://demo.mercure.com", "https://example.com"},
      {"https://mercure.internal.com", "https://external.com"},
    }
  end

  def test_set_multiple_cookies : Nil
    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      "https://example.com/.well-known/mercure",
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: AMC::TokenFactory::JWT.new("looooooooooooongenoughtestsecret", jwt_lifetime: 4000)
    ) { "ID" })

    request = HTTP::Request.new("GET", "https://example.com", headers: HTTP::Headers{"host" => "example.com"})
    response = HTTP::Server::Response.new IO::Memory.new

    authorization = AMC::Authorization.new registry

    expect_raises AMC::Exceptions::Runtime, "The 'mercureAuthorization' cookie for the 'default hub' has already been set. You cannot set it two times during the same request." do
      authorization.set_cookie request, response
      authorization.clear_cookie request, response
    end
  end

  def test_nil_cookie_topics : Nil
    token_factory = AssertingTokenFactory.new(
      "JWT",
      nil,
      nil,
      {"x-foo" => "baz"},
    )

    registry = AMC::Hub::Registry.new(AMC::Hub::Mock.new(
      "https://example.com/.well-known/mercure",
      AMC::TokenProvider::Static.new("JWT"),
      token_factory: token_factory
    ) { "ID" })

    request = HTTP::Request.new("GET", "https://example.com", headers: HTTP::Headers{"host" => "example.com"})
    response = HTTP::Server::Response.new IO::Memory.new

    authorization = AMC::Authorization.new registry
    authorization.set_cookie request, response, nil, nil, {"x-foo" => "baz"}

    cookie = response.cookies.first
    cookie.value.should_not be_empty
  end
end
