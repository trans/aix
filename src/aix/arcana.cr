require "http/client"
require "json"
require "uri"

module Aix
  # Native HTTP client for the Arcana bus. AIX talks to Arcana directly over
  # its HTTP API (default http://127.0.0.1:19118) rather than through the MCP
  # shim — this is what lets AIX act as the bus bridge.
  #
  # Endpoints used: POST /register, POST /deliver, POST /receive (long-poll),
  # GET /events (audit log). Events model each fact as a subject-predicate-
  # object triple. NOTE: for `message.sent`, `subject` is the recipient (the
  # `to`) and `object` is the sender — verified live against the bus.
  class Arcana
    DEFAULT_URL = "http://127.0.0.1:19118"

    getter address : String
    getter base_uri : URI

    def initialize(@address : String, base_url : String? = nil)
      @base_uri = URI.parse(base_url || ENV["ARCANA_URL"]? || DEFAULT_URL)
    end

    def register(name : String? = nil, description : String? = nil,
                 tags : Array(String)? = nil, kind : String = "agent") : JSON::Any
      post("/register", {
        address: @address, name: name, description: description,
        kind: kind, tags: tags,
      }.to_json)
    end

    # Fire a message at another address. `ordering: async` = fire-and-forget.
    def deliver(to : String, message : String, subject : String = "",
                ordering : String = "async") : JSON::Any
      post("/deliver", {
        from: @address, to: to, subject: subject,
        payload: {message: message}, ordering: ordering, timeout_ms: 30_000,
      }.to_json)
    end

    # Long-poll our own mailbox. Blocks server-side up to timeout_ms for the
    # first message, then drains the rest. Returns an array of envelopes.
    def receive(timeout_ms : Int32 = 0) : Array(JSON::Any)
      result = post("/receive", {address: @address, timeout_ms: timeout_ms}.to_json,
        read_timeout: (timeout_ms / 1000.0) + 15.0)
      result.as_a? || [] of JSON::Any
    end

    # Query the audit event log. On a message.sent event, `subject` is the
    # recipient — the address to wake.
    def events(type : String? = nil, since : String? = nil,
               subject : String? = nil, limit : Int32 = 100) : Array(JSON::Any)
      params = URI::Params.build do |p|
        p.add("type", type) if type
        p.add("since", since) if since && !since.empty?
        p.add("subject", subject) if subject
        p.add("limit", limit.to_s)
      end
      result = get("/events?#{params}")
      result.as_a? || [] of JSON::Any
    end

    private def get(path : String) : JSON::Any
      parse(HTTP::Client.get(@base_uri.resolve(path)))
    end

    private def post(path : String, body : String, read_timeout : Float64? = nil) : JSON::Any
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      if read_timeout
        client = HTTP::Client.new(@base_uri)
        client.read_timeout = read_timeout.seconds
        begin
          parse(client.post(path, headers: headers, body: body))
        ensure
          client.close
        end
      else
        parse(HTTP::Client.post(@base_uri.resolve(path), headers: headers, body: body))
      end
    end

    private def parse(response : HTTP::Client::Response) : JSON::Any
      JSON.parse(response.body)
    rescue
      JSON::Any.new(nil)
    end
  end
end
