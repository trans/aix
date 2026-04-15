require "crt"
require "./session_manager"

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
        items = build_items

        # -- Header bar --
        CRT::Label.new(screen, x: 0, y: 0, width: sw, height: 1,
          text: " AIX v#{VERSION}", style: CRT.theme.field)

        # -- Sidebar: project list --
        list_height = sh - 4 # header + footer + border top/bottom
        list = CRT::ListBox.new(screen, x: 0, y: 1,
          items: items,
          width: SIDEBAR_WIDTH,
          height: list_height,
          border: CRT::Border::Single)

        # -- Resume checkbox (below list, in sidebar area) --
        resume_y = 1 + list_height
        resume_cb = CRT::Checkbox.new(screen, x: 1, y: resume_y,
          text: "Resume conversation")

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

        update_detail = ->(index : Int32) {
          session = @manager.sessions[index]?
          if session
            state_text = case session.state
                         when SessionState::Running then "Running"
                         when SessionState::Cold    then "Not started"
                         else                            "Stopped"
                         end
            detail.text = "#{session.name}\n\n" \
                          "Directory: #{session.directory}\n" \
                          "Status:    #{state_text}\n\n" \
                          "Enter to open, Tab to navigate"
          else
            detail.text = ""
          end
          nil
        }

        # -- Footer bar --
        footer_y = sh - 1
        CRT::Label.new(screen, x: 0, y: footer_y, width: sw, height: 1,
          text: " Enter:Open  a:Add  d:Drop  q:Quit", style: CRT.theme.field)

        # -- Sync resume checkbox with session state --
        sync_resume = ->(index : Int32) {
          session = @manager.sessions[index]?
          if session && session.running?
            resume_cb.check
          end
          nil
        }

        resume_cb.on_change = ->(checked : Bool) {
          session = @manager.sessions[list.selected]?
          if session && session.running? && !checked
            resume_cb.check
          end
          nil
        }

        # Set initial state
        sync_resume.call(list.selected)
        update_detail.call(list.selected)

        list.on_change = ->(index : Int32) {
          sync_resume.call(index)
          update_detail.call(index)
          nil
        }

        open_action = ->{
          index = list.selected
          session = @manager.sessions[index]?
          if session
            @manager.switch(session.name)
            unless session.running?
              args = if resume_cb.checked?
                       if id = session.claude_session_id
                         ["--resume", id]
                       else
                         ["--continue"]
                       end
                     else
                       [] of String
                     end
              session.start(args)
              @manager.persist_sessions
            end
            selected_name = session.name
          end
          nil
        }

        list.on_activate = ->(_index : Int32) {
          open_action.call
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
              elsif !event.ctrl? && event.char == "d"
                unless screen.focused_widget.is_a?(CRT::Entry)
                  index = list.selected
                  session = @manager.sessions[index]?
                  if session
                    @manager.remove(session.name)
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

    # Screen for adding a new project.
    private def run_new_screen : Symbol
      path : String? = nil
      cancelled = false

      CRT::Screen.open(alt_screen: true, raw_mode: true, hide_cursor: true) do |screen|
        sw = screen.width
        sh = screen.height

        # Header
        CRT::Label.new(screen, x: 0, y: 0, width: sw, height: 1,
          text: " Add Project", style: CRT.theme.field)

        CRT::Label.new(screen, x: 2, y: 3, text: "Directory:")

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
        expanded = SessionManager.expand_directory(p)
        name = File.basename(expanded)
        begin
          @manager.add(name, expanded)
        rescue ex
          File.write("/tmp/aix-debug.log", "ADD failed: #{ex.message}\npath=#{p}\nexpanded=#{expanded}\nname=#{name}\n")
        end
      end

      run
    end

    private def build_items : Array(String)
      @manager.sessions.map do |s|
        status = case s.state
                 when SessionState::Running then "●"
                 when SessionState::Cold    then "○"
                 else                            "✕"
                 end
        "#{status} #{s.name}"
      end
    end
  end
end
