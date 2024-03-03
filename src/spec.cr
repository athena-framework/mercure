module Athena::Mercure
  struct Hub::Mock
    include Athena::Mercure::Hub::Interface

    getter url : String
    getter token_provider : AMC::TokenProvider::Interface
    getter token_factory : AMC::TokenFactory::Interface?

    @publisher : Proc(AMC::Update, String)

    def initialize(
      @url : String,
      @token_provider : AMC::TokenProvider::Interface,
      @public_url : String? = nil,
      @token_factory : AMC::TokenFactory::Interface? = nil,
      &@publisher : AMC::Update -> String
    )
    end

    def public_url : String
      @public_url || @url
    end

    def publish(update : AMC::Update) : String
      @publisher.call update
    end
  end
end
