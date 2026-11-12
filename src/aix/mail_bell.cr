require "socket"
require "./bell"
require "./config"
require "./inotify"

module Aix
  # Rings the bell when mail reaches a project whose agent runs in aix.
  #
  # dot-ai's carrier puts mail straight into each project's
  # `.ai/mail/inbox/`, never touching the bus, so this watches the inboxes
  # themselves (with inotify: nothing polls for mail), in the projects the
  # carrier finds (git config's `ai.path`), not only aix's roots. When a
  # message lands, it rings the project's window. If the bell is held (the
  # user is typing there, a draft is in the box, a dialog is up), it tries
  # again every few seconds until the inbox has been read or the window is
  # gone, and flashes a message for the user meanwhile.
  #
  # Projects are found at the start, and again on `aix update`, which
  # reaches the bell through a socket it listens on; no timer searches. The
  # carrier never makes an inbox (mail for a project without one stays in
  # the sender's outbox), so a new one appears only when a project is set
  # up. The socket also keeps the bell to one per user: a second finds the
  # first listening and doesn't start.
  class MailBell
    RETRY_EVERY   = 5.seconds
    GIVE_UP_AFTER = 1.hour

    def self.socket_path : String
      File.join(Bell.runtime_dir, "bell.sock")
    end

    # Send one request to the running bell and return its answer, or nil
    # when no bell is listening.
    def self.request(line : String) : String?
      UNIXSocket.open(socket_path) do |socket|
        socket.puts line
        socket.flush
        socket.gets
      end
    rescue Socket::ConnectError | File::NotFoundError | IO::Error | ArgumentError
      nil # ArgumentError: a path too long for a socket, so no bell listens there
    end

    @inotify : Inotify?
    @server : UNIXServer?

    def initialize
      @window_for = {} of String => String    # inbox directory => window name
      @pending = {} of String => Time::Instant # window => held since
      @inbox_of = {} of String => String      # window => inbox directory
    end

    # Take the socket. False if another bell already has it. A bell that
    # can't have one (its path too long for a socket) runs without: it rings,
    # but `aix update` can't reach it.
    def listen : Bool
      path = MailBell.socket_path
      Dir.mkdir_p(File.dirname(path))
      if File.exists?(path)
        return false if MailBell.request("ping")
        File.delete(path) # left by a bell that didn't exit cleanly
      end
      @server = UNIXServer.new(path)
      true
    rescue ex : ArgumentError | Socket::Error
      log "can't listen at #{path} (#{ex.message}): `aix update` won't reach this bell"
      true
    end

    def run
      unless Inotify.available?
        log "watching inboxes needs Linux's inotify: the bell won't ring for dot-ai mail"
        @server.try(&.close)
        return
      end
      inotify = @inotify = Inotify.new
      log watch_projects(inotify)
      spawn retry_loop
      if server = @server
        spawn serve(server)
      end
      inotify.each_new_file do |dir, name|
        next if name.starts_with?('.') || !name.ends_with?(".md")
        if window = @window_for[dir]?
          ring(window, first: true)
        end
      end
    end

    # Watch the inbox of every project dot-ai's carrier delivers to
    # (`Config.mail_search`), and forget the ones no longer found. Projects
    # whose agents aren't running in aix are watched too; the bell finds no
    # window for them and does nothing. Returns what changed.
    private def watch_projects(inotify : Inotify) : String
      window_for = {} of String => String
      Config.mail_search.discover.each do |project|
        inbox = File.join(project.directory, ".ai", "mail", "inbox")
        next unless Dir.exists?(inbox)
        window_for[inbox] = project.name if inotify.watching?(inbox) || inotify.watch(inbox)
      end
      added = (window_for.keys - @window_for.keys).size
      gone = (@window_for.keys - window_for.keys).size
      @window_for = window_for
      @inbox_of = window_for.invert
      "watching #{window_for.size} inbox(es): #{added} new, #{gone} gone"
    rescue ex
      "discovery failed: #{ex.message}"
    end

    # Answer requests on the socket, one line each: `update` (search for
    # projects again) or `ping`.
    private def serve(server : UNIXServer)
      while client = server.accept?
        spawn answer(client)
      end
    end

    private def answer(client : UNIXSocket)
      line = client.gets.try(&.strip) || return
      reply = case line
              when "ping"   then "pong"
              when "update" then update
              else               "unknown request: #{line}"
              end
      client.puts reply
      client.flush
    rescue IO::Error
    ensure
      client.close
    end

    private def update : String
      inotify = @inotify || return "the bell isn't watching inboxes"
      result = watch_projects(inotify)
      log "update: #{result}"
      result
    end

    private def ring(window : String, first : Bool = false)
      result, reason = Bell.ring(window)
      log "#{window}: #{result.to_s.downcase}, #{reason}" if first || !result.held?
      if result.held?
        unless @pending.has_key?(window)
          @pending[window] = Time.instant
          Tmux.display_message("aix: mail for @#{window} (#{reason})")
        end
      else
        @pending.delete(window)
      end
    end

    # Ring held windows again until they're told, their inbox has been
    # read, their window is gone, or it's been too long.
    private def retry_loop
      loop do
        sleep RETRY_EVERY
        @pending.keys.each do |window|
          since = @pending[window]
          if !unread?(window)
            @pending.delete(window)
          elsif Time.instant - since > GIVE_UP_AFTER
            log "#{window}: gave up after #{GIVE_UP_AFTER.total_minutes.to_i} minutes held"
            @pending.delete(window)
          else
            ring(window)
          end
        end
      end
    end

    # Whether a window's project still has mail in its inbox.
    private def unread?(window : String) : Bool
      inbox = @inbox_of[window]? || return false
      Dir.children(inbox).any? { |name| !name.starts_with?('.') && name.ends_with?(".md") }
    rescue
      false
    end

    private def log(message : String)
      STDERR.puts "[aix-bell] #{message}"
      STDERR.flush
    end
  end
end
