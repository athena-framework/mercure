struct Athena::Mercure::TokenFactory::JWT
  include Athena::Mercure::TokenFactory::Interface

  @jwt_lifetime : Time::Span?

  def initialize(
    @jwt_secret : String,
    @algorithm : JWT::Algorithm = :hs256,
    jwt_lifetime : Int32 | Time::Span | Nil = 3600,
    @passphrase : String = ""
  )
    @jwt_lifetime = jwt_lifetime.is_a?(Int32) ? jwt_lifetime.seconds : jwt_lifetime
  end

  def create(
    subscribe : Array(String)? = [] of String,
    publish : Array(String)? = [] of String,
    additional_claims : Hash = {} of NoReturn => NoReturn
  ) : String
    if !@jwt_lifetime.nil? && !additional_claims.has_key? "exp"
      additional_claims["exp"] = @jwt_lifetime.total_seconds
    end

    tokens = {} of String => String | Array(String)
    unless subscribe.empty?
      tokens["subscribe"] = subscribe
    end

    unless publish.empty?
      tokens["publish"] = publish
    end

    additional_claims["mercure"] = tokens

    if mercure_claims = additional_claims["mercure"]
      additional_claims["mercure"].merge! mercure_claims
    end

    JWT.encode additional_claims, @jwt_secret, @algorithm
  end
end
