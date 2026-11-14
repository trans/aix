require "crt"
require "./session_manager"
require "./screens"

module Aix
  class TUI
    SIDEBAR_WIDTH = 32

    getter manager : SessionManager

    def initialize(@manager : SessionManager)
    end

    # Show the project list. Returns :switch when user selects a session,
    # or :quit on Ctrl-C / q.
    def run : Symbol
      selected_name : String? = nil
      quit = false
      refresh = false
      add_new = false

      CRT::Screen.open(alt_screen: true, raw_mode: true, hide_cursor: true) do |screen|
        sw = screen.width
        sh = screen.height
        elsewhere = Conversations.elsewhere
        items = build_items(elsewhere)

        # -- Header bar --
        CRT::Label.new(screen, x: 0, y: 0, width: sw, height: 1,
          text: " AIX v#{VERSION}", style: CRT.theme.field)

        # -- Sidebar: project list --
        list_height = sh - 2 # between header and footer, as the panel
        list = CRT::ListBox.new(screen, x: 0, y: 1,
          items: items,
          width: SIDEBAR_WIDTH,
          height: list_height,
          border: CRT::Border::Single)

        # -- Right panel: session detail --
        detail_x = SIDEBAR_WIDTH
        detail_w = sw - SIDEBAR_WIDTH
        detail_h = sh - 2 # between header and footer

        detail = CRT::Label.new(screen, x: detail_x, y: 1,
          width: detail_w, height: detail_h,
          text: "", border: CRT::Border::Single,
          align: CRT::Ansi::Align::Left,
          valign: CRT::Ansi::VAlign::Top,
          pad: 1)

        # The selected project, where else it's open, then its agent's
        # screen: live if it's running, else as it was when aix last saw it
        # (`Screens`). `notice` goes in place of the screen.
        screen_w = detail_w - 4 # border and padding
        screen_h = detail_h - 6 # border, padding, the title and a blank line
        # Where projects are open outside aix, looked at again when it's
        # more than a moment old.
        elsewhere_at = Time.instant
        current_elsewhere = -> {
          if Time.instant - elsewhere_at > 2.seconds
            elsewhere = Conversations.elsewhere
            elsewhere_at = Time.instant
          end
          elsewhere
        }
        show_detail = ->(index : Int32, notice : String?) {
          session = @manager.sessions[index]?
          if session
            running = session.running?
            state_text = running ? "running" : "not running"
            where = session.directory.sub(/\A#{Regex.escape(Path.home.to_s)}/, "~")
            above = session.parent ? "  ·  below #{session.parent}" : ""
            title = Screens.fit("#{session.name}  ·  #{session.harness.label}, #{state_text}  ·  #{where}#{above}", screen_w, 1)
            others = Conversations.in(current_elsewhere.call, session.directory).first(3).map do |open|
              Screens.fit("Also open: #{Conversations.describe(open)}", screen_w, 1)
            end
            body = if notice
                     Screens.wrap(notice, screen_w)
                   else
                     shown = Screens.preview(session.name, screen_w, screen_h - others.size)
                     shown || (running ? "(its screen can't be read)" : "No screen saved yet: Enter starts its agent.")
                   end
            detail.text = ([title] + others).join("\n") + "\n\n#{body}"
          else
            detail.text = ""
          end
          nil
        }
        update_detail = ->(index : Int32) { show_detail.call(index, nil) }

        # -- Footer bar --
        footer_y = sh - 1
        CRT::Label.new(screen, x: 0, y: footer_y, width: sw, height: 1,
          text: " Enter:Open  n:New conversation  h:Harness  a:Add Root  d:Stop  q:Quit", style: CRT.theme.field)

        update_detail.call(list.selected)

        list.on_change = ->(index : Int32) {
          update_detail.call(index)
          nil
        }

        # Go to the selected project's agent, starting it if it isn't
        # running: in its last conversation (`Session#resume_args`, a new
        # one where there's none), or, with `fresh`, in a new one.
        open_action = ->(fresh : Bool) {
          index = list.selected
          session = @manager.sessions[index]?
          if session && session.running? && fresh
            show_detail.call(index, "It's running: Enter goes to it, and d stops it, to start a new conversation.")
          elsif session
            refusal = session.running? || fresh ? nil : session.resume_refusal
            if refusal
              # Another program holds the conversation: say so, and stay.
              show_detail.call(index, "Not resumed: #{refusal}\nn starts a new one.")
            else
              @manager.switch(session.name)
              unless session.running?
                session.start(fresh ? [] of String : session.resume_args)
                @manager.persist_sessions
              end
              selected_name = session.name
            end
          end
          nil
        }

        list.on_activate = ->(_index : Int32) {
          open_action.call(false)
          nil
        }

        screen.focus(list)

        screen.run(fps: 30) do
          screen.each_event do |event|
            case event
            when CRT::Key
              if event.ctrl? && event.char == "c"
                quit = true
              elsif !event.ctrl? && event.char == "q"
                quit = true unless screen.focused_widget.is_a?(CRT::Entry)
              elsif !event.ctrl? && event.char == "a"
                add_new = true unless screen.focused_widget.is_a?(CRT::Entry)
              elsif !event.ctrl? && event.char == "n"
                open_action.call(true) unless screen.focused_widget.is_a?(CRT::Entry)
              elsif !event.ctrl? && event.char == "h"
                # Switch the selected project between Claude Code and
                # Codex, from its next start: not while its agent runs.
                index = list.selected
                session = @manager.sessions[index]?
                if session && !session.running? && !screen.focused_widget.is_a?(CRT::Entry)
                  other = session.harness.claude? ? Harness::Kind::Codex : Harness::Kind::Claude
                  @manager.set_harness(session.name, other)
                  update_detail.call(index)
                end
              elsif !event.ctrl? && event.char == "d"
                unless screen.focused_widget.is_a?(CRT::Entry)
                  index = list.selected
                  session = @manager.sessions[index]?
                  if session
                    @manager.stop(session.name)
                    refresh = true
                  end
                end
              else
                screen.dispatch(event)
              end
            else
              screen.dispatch(event)
            end
          end
          break if selected_name
          break if quit
          break if refresh
          break if add_new
        end
      end

      return run_new_screen if add_new
      return run if refresh
      return :quit if quit
      return :switch if selected_name
      :quit
    end

    # Screen for adding a new root path. Projects under it are then
    # discovered automatically (any directory containing a .ai/).
    private def run_new_screen : Symbol
      path : String? = nil
      cancelled = false

      CRT::Screen.open(alt_screen: true, raw_mode: true, hide_cursor: true) do |screen|
        sw = screen.width
        sh = screen.height

        # Header
        CRT::Label.new(screen, x: 0, y: 0, width: sw, height: 1,
          text: " Add Root Path", style: CRT.theme.field)

        CRT::Label.new(screen, x: 2, y: 3, text: "Root path (scanned for .ai/ projects):")

        entry = CRT::Entry.new(screen, x: 2, y: 4, width: {sw - 4, 60}.min,
          border: CRT::Border::Single) do |value|
          path = value unless value.strip.empty?
        end

        # Footer
        CRT::Label.new(screen, x: 0, y: sh - 1, width: sw, height: 1,
          text: " Enter:Confirm  Ctrl-C:Cancel", style: CRT.theme.field)

        screen.focus(entry)

        screen.run(fps: 30) do
          screen.each_event do |event|
            case event
            when CRT::Key
              if event.ctrl? && event.char == "c"
                cancelled = true
              end
            end
            screen.dispatch(event)
          end
          break if path
          break if cancelled
        end
      end

      if p = path
        @manager.add_root(p.strip)
      end

      run
    end

    # The list: each project with a mark for its agent. ● running in aix,
    # ◐ open in another program, ○ not started, ✕ stopped.
    private def build_items(elsewhere : Hash(String, Array(Conversations::Open))) : Array(String)
      return ["(no projects — press 'a' to add a root)"] if @manager.sessions.empty?

      @manager.sessions.map do |s|
        status = if s.running?
                   "●"
                 elsif !Conversations.in(elsewhere, s.directory).empty?
                   "◐"
                 elsif s.cold?
                   "○"
                 else
                   "✕"
                 end
        "#{"  " * s.level}#{status} #{s.name}"
      end
    end
  end
end
