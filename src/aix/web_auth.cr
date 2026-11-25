require "http"
require "crypto/subtle"
require "random/secure"

module Aix
  # Who may use aix's web interface. It can type into agents, which can
  # run commands, so a web page in the person's browser mustn't reach it:
  # browsers let any site open a WebSocket to 127.0.0.1, and a site can
  # make its own domain name point there (DNS rebinding). So every request
  # needs:
  #
  # - a `Host` of the address aix listens on (when that's this machine
  #   only), which a rebound domain isn't;
  # - an `Origin`, if the browser sends one (it does for WebSockets and
  #   for scripts' requests), of that same address;
  # - aix's secret, as a cookie. The address aix prints at its start
  #   carries it (`?token=`); opening that sets the cookie and moves on to
  #   the address without it. The cookie isn't sent with another site's
  #   requests (`SameSite=Strict`), nor readable by scripts (`HttpOnly`).
  #
  # The secret is kept in a file only the person can read, so the address
  # stays the same from one start to the next.
  class WebAuth
    include HTTP::Handler

    COOKIE   = "aix_token"
    LOOPBACK = {"127.0.0.1", "localhost", "::1", "[::1]"}

    getter token : String

    def initialize(@token : String, @host : String, @port : Int32)
    end

    # The secret, from its file, made if there's none.
    def self.load_token(path : String = token_path) : String
      existing = File.read(path).strip rescue ""
      return existing unless existing.empty?
      Dir.mkdir_p(File.dirname(path))
      File.chmod(File.dirname(path), 0o700)
      token = Random::Secure.urlsafe_base64(32)
      File.open(path, "w", perm: 0o600) { |file| file.puts token }
      token
    end

    def self.token_path : String
      base = ENV["XDG_STATE_HOME"]? || File.join(Path.home, ".local", "state")
      File.join(base, "aix", "web-token")
    end

    # Whether aix listens on this machine only.
    def loopback? : Bool
      LOOPBACK.includes?(@host)
    end

    # The address to open, with the secret.
    def address : String
      host = @host.includes?(':') && !@host.starts_with?('[') ? "[#{@host}]" : @host
      host = "127.0.0.1" if {"0.0.0.0", "[::]"}.includes?(host)
      "http://#{host}:#{@port}/?token=#{@token}"
    end

    def call(context : HTTP::Server::Context)
      request = context.request
      host = request.headers["Host"]?
      return refuse(context, 403, "This address isn't aix's.") unless allowed_host?(host)
      if (origin = request.headers["Origin"]?) && origin != "http://#{host}"
        return refuse(context, 403, "Requests from other sites aren't accepted.")
      end

      if given = request.query_params["token"]?
        return refuse(context, 403, "That isn't aix's address: open the one aix printed at its start.") unless secret?(given)
        context.response.cookies << HTTP::Cookie.new(COOKIE, @token, path: "/", http_only: true,
          samesite: HTTP::Cookie::SameSite::Strict, max_age: 365.days)
        context.response.status_code = 303
        context.response.headers["Location"] = request.path
        return
      end

      unless secret?(request.cookies[COOKIE]?.try(&.value))
        return refuse(context, 401, "Open the address aix printed at its start (it ends in ?token=…).")
      end
      call_next(context)
    end

    # Whether `host` (a `Host` header) is the address aix listens on. When
    # it listens beyond this machine, any name may reach it, so only the
    # secret guards it.
    def allowed_host?(host : String?) : Bool
      return false unless host
      return true unless loopback?
      name, _, port = host.rpartition(':')
      port == @port.to_s && LOOPBACK.includes?(name)
    end

    private def secret?(given : String?) : Bool
      !!given && Crypto::Subtle.constant_time_compare(given, @token)
    end

    private def refuse(context, status : Int32, message : String)
      context.response.status_code = status
      context.response.content_type = "text/plain"
      context.response.print "aix: #{message}\n"
    end
  end
end
