require "./interface"

class Athena::Mercure::Hub
  include Athena::Mercure::Hub::Interface

  getter url : String
  getter token_provider : AMC::TokenProvider::Interface
  getter token_factory : AMC::TokenFactory::Interface?

  @public_url : String?

  def initialize(
    @url : String,
    @token_provider : AMC::TokenProvider::Interface,
    @public_url : String? = nil,
    @token_factory : AMC::TokenFactory::Interface? = nil
  )
  end

  def public_url : String
    @public_url || @url
  end

  def publish(update : AMC::Update) : String
    HTTP::Client.post(
      @url,
      headers: HTTP::Headers{
        "Authorization" => "Bearer #{@token_provider.jwt}",
      },
      form: URI::Params.build do |form|
        self.encode form, update
      end
    ).body
  end

  private def encode(form : URI::Params::Builder, update : AMC::Update) : Nil
    form.add "topic", update.topics
    form.add "data", update.data

    if update.private?
      form.add "private", "on"
    end

    if id = update.id
      form.add "id", id
    end

    if type = update.type
      form.add "type", type
    end

    if retry = update.retry
      form.add "retry", retry.to_s
    end
  end
end
