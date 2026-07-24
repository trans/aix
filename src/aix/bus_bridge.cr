require "./arcana"
require "./tmux"

module Aix
  # The bus bridge — AIX's "nervous system" that makes reactive tmux harnesses
  # behave like live participants on the Arcana bus.
  #
  # A Claude Code sub-agent is turn-based: it acts, then blocks on stdin. Mail
  # sitting in its Arcana mailbox does nothing until something types into its
  # pane. AIX owns the panes AND can watch the bus, so it converts bus activity
  # into keystroke wake-ups:
  #
  #   bus: message.sent, subject=@beta   ==>   tmux: send_keys(beta, "check mail")
  #   (on message.sent, `subject` is the recipient/`to`; `object` is the sender)
  #
  # It also parks on its own @aix mailbox (server-side long-poll) as the channel
  # sub-agents report back on.
  class BusBridge
    ADDRESS       = "@aix"
    WAKE_TEXT     = "New Arcana mail for you — run arcana_receive to read and handle it."
    COOLDOWN      = 3.seconds
    POLL_INTERVAL = 750.milliseconds

    def initialize(base_url : String? = nil)
      @arcana = Arcana.new(ADDRESS, base_url)
      @seen = Set(String).new
      @last_nudge = {} of String => Time::Instant
      @cursor = ""
    end

    def run
      log "registering #{ADDRESS} on #{@arcana.base_uri}"
      @arcana.register(name: "AIX", description: "AIX bus bridge", tags: ["orchestrator", "multiplexer"])
      bootstrap_cursor
      spawn inbox_listener
      poll_loop
    end

    # Seed the cursor from current bus state so we don't replay old history,
    # using SERVER-provided timestamps (the Arcana clock differs from ours).
    private def bootstrap_cursor
      recent = @arcana.events(type: "message.sent", limit: 200)
      recent.each do |ev|
        if id = ev["id"]?.try(&.as_s)
          @seen << id
        end
        if ts = ev["timestamp"]?.try(&.as_s)
          @cursor = ts if ts > @cursor
        end
      end
      log "cursor start: #{@cursor.presence || "(none)"} — #{recent.size} events pre-seen"
    end

    # TODO(pubsub): Replace this poll loop with a push subscription. Arcana
    # already has topics (POST /publish + subscribe). Add a system firehose
    # topic (e.g. "sys.message.sent") that Arcana tees every delivery to, then
    # subscribe @aix and long-poll /receive on it — same mechanism as the
    # inbox listener below, but instant and poll-free. See TODO.md.
    private def poll_loop
      loop do
        begin
          targets = Set(String).new
          @arcana.events(type: "message.sent", since: @cursor).each do |ev|
            id = ev["id"]?.try(&.as_s)
            next if id.nil? || @seen.includes?(id)
            @seen << id
            if ts = ev["timestamp"]?.try(&.as_s)
              @cursor = ts if ts > @cursor
            end
            # On a message.sent event the RECIPIENT is `subject` (the `to`);
            # `object` is the sender. Verified live against the bus.
            if recipient = ev["subject"]?.try(&.as_s)
              targets << recipient
            end
          end
          targets.each { |addr| maybe_nudge(addr) }
          trim_seen
        rescue ex
          log "poll error: #{ex.message}"
        end
        sleep POLL_INTERVAL
      end
    end

    # Wake the tmux session backing `address`, if one exists and isn't in
    # cooldown. Convention: bus handle "@beta" <-> tmux window "beta".
    private def maybe_nudge(address : String)
      return if address == ADDRESS # our own inbox is handled by the listener
      name = address.lstrip('@')
      return unless Tmux.window_exists?(name)

      now = Time.instant
      if last = @last_nudge[name]?
        return if (now - last) < COOLDOWN
      end
      @last_nudge[name] = now

      Tmux.send_keys(name, WAKE_TEXT)
      log "nudged '#{name}' (mail for #{address})"
    end

    # Park on our own mailbox. Sub-agents report/ask here; the server-side
    # long-poll gives push-quality latency with no polling.
    private def inbox_listener
      loop do
        begin
          @arcana.receive(timeout_ms: 25_000).each do |envelope|
            # TODO(leader): surface/relay these to the Leader instead of just
            # logging — this is the sub-agent -> Leader reporting channel.
            log "inbox <= #{envelope.to_json}"
          end
        rescue ex
          log "inbox error: #{ex.message}"
          sleep 1.second
        end
      end
    end

    private def trim_seen
      @seen.clear if @seen.size > 5000
    end

    private def log(message : String)
      STDERR.puts "[aix-bridge] #{message}"
      STDERR.flush
    end
  end
end
