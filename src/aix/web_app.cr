require "html"
require "json"
require "kemal"

module Aix
  module WebApp
    extend self

    SNAPSHOT_LINES = 40
    PREVIEW_LINES = 12
    SNAPSHOT_INTERVAL = 300.milliseconds

    @@manager : SessionManager?
    @@lock = Mutex.new

    get "/" do |env|
      env.response.content_type = "text/html"
      dashboard_page
    end

    get "/sessions/:name" do |env|
      name = env.params.url["name"]
      unless with_lock { manager.find(name) }
        env.response.status_code = 404
        next "No session named '#{name}'"
      end

      env.response.content_type = "text/html"
      session_page(name)
    end

    get "/api/sessions" do |env|
      sessions = with_lock do
        manager.sessions.map { |session| session_payload(session, PREVIEW_LINES) }
      end
      json_response(env, {sessions: sessions})
    end

    get "/api/sessions/:name" do |env|
      name = env.params.url["name"]

      payload = with_lock do
        session = manager.find(name)
        session ? session_payload(session, SNAPSHOT_LINES) : nil
      end

      if payload
        json_response(env, payload)
      else
        json_response(env, {error: "No session named '#{name}'"}, 404)
      end
    end

    get "/api/roots" do |env|
      roots, depth = with_lock { {manager.config.roots, manager.config.depth} }
      json_response(env, {roots: roots, depth: depth})
    end

    post "/api/roots" do |env|
      payload = request_payload(env)
      path = payload["path"]?.try(&.as_s?) || ""

      if path.blank?
        next json_response(env, {error: "Root path is required"}, 422)
      end

      begin
        added = with_lock { manager.add_root(path) }
        next json_response(env, {error: "Root '#{path}' is already configured"}, 422) unless added
        json_response(env, {ok: true, count: with_lock { manager.sessions.size }}, 201)
      rescue ex
        json_response(env, {error: ex.message}, 422)
      end
    end

    delete "/api/roots" do |env|
      payload = request_payload(env)
      path = payload["path"]?.try(&.as_s?) || ""

      begin
        removed = with_lock { manager.remove_root(path) }
        next json_response(env, {error: "No such root '#{path}'"}, 404) unless removed
        json_response(env, {ok: true})
      rescue ex
        json_response(env, {error: ex.message}, 422)
      end
    end

    post "/api/sessions/:name/start" do |env|
      name = env.params.url["name"]
      payload = request_payload(env)
      resume = payload["resume"]?.try(&.as_bool?) || false

      begin
        session = with_lock do
          existing = manager.find(name)
          raise "No session named '#{name}'" unless existing
          unless existing.running?
            args = if resume
                     if id = existing.claude_session_id
                       ["--resume", id]
                     else
                       ["--continue"]
                     end
                   else
                     [] of String
                   end
            manager.start(name, args)
            manager.persist_sessions
          end
          manager.find(name).not_nil!
        end
        json_response(env, {session: session_payload(session, SNAPSHOT_LINES)})
      rescue ex
        json_response(env, {error: ex.message}, 422)
      end
    end

    post "/api/sessions/:name/stop" do |env|
      name = env.params.url["name"]

      begin
        session = with_lock do
          existing = manager.find(name)
          raise "No session named '#{name}'" unless existing
          existing.stop
          existing
        end
        json_response(env, {session: session_payload(session, PREVIEW_LINES)})
      rescue ex
        json_response(env, {error: ex.message}, 422)
      end
    end

    post "/api/refresh" do |env|
      count = with_lock do
        manager.refresh
        manager.sessions.size
      end
      json_response(env, {ok: true, count: count})
    end

    ws "/ws/sessions/:name" do |socket, env|
      name = env.params.url["name"]

      unless with_lock { manager.find(name) }
        socket.send({type: "error", error: "No session named '#{name}'"}.to_json)
        socket.close
        next
      end

      closed = false

      spawn do
        last_frame = ""

        until closed
          begin
            frame = with_lock { websocket_frame(name) }
            encoded = frame.to_json
            if encoded != last_frame
              socket.send(encoded)
              last_frame = encoded
            end
          rescue
            break
          end

          sleep SNAPSHOT_INTERVAL
        end
      end

      socket.on_message do |message|
        begin
          payload = JSON.parse(message)
          with_lock { handle_socket_message(name, payload) }
        rescue
          # Ignore malformed or stale client messages.
        end
      end

      socket.on_close do
        closed = true
      end
    end

    error 404 do |env|
      env.response.content_type = "text/plain"
      "Not found"
    end

    def run(host : String, port : Int32)
      Tmux.ensure_session
      config = Kemal.config
      config.host_binding = host
      config.port = port
      Kemal.run
    end

    private def manager : SessionManager
      @@manager ||= SessionManager.new
    end

    private def with_lock(&)
      @@lock.synchronize { yield }
    end

    private def request_payload(env) : Hash(String, JSON::Any)
      body = env.request.body
      return {} of String => JSON::Any unless body

      content = body.gets_to_end
      return {} of String => JSON::Any if content.blank?

      JSON.parse(content).as_h
    rescue
      {} of String => JSON::Any
    end

    private def json_response(env, payload, status_code = 200)
      env.response.status_code = status_code
      env.response.content_type = "application/json"
      payload.to_json
    end

    private def session_payload(session : Session, preview_lines : Int32)
      preview = if session.running?
                  Tmux.capture_pane(session.name, preview_lines).rstrip
                else
                  ""
                end

      {
        name: session.name,
        directory: session.directory,
        state: session.state.to_s,
        running: session.running?,
        preview: preview,
      }
    rescue
      {
        name: session.name,
        directory: session.directory,
        state: session.state.to_s,
        running: false,
        preview: "",
      }
    end

    private def websocket_frame(name : String)
      session = manager.find(name)
      return {type: "error", error: "No session named '#{name}'"} unless session

      {
        type: "snapshot",
        name: session.name,
        state: session.state.to_s,
        running: session.running?,
        text: session.running? ? Tmux.capture_pane(session.name, SNAPSHOT_LINES).rstrip : "",
      }
    end

    private def handle_socket_message(name : String, payload : JSON::Any)
      session = manager.find(name)
      return unless session && session.running?

      case payload["type"]?.try(&.as_s?)
      when "command"
        text = payload["text"]?.try(&.as_s?) || ""
        return if text.empty?
        Tmux.send_literal(name, text)
        Tmux.send_key(name, "Enter")
      when "input"
        text = payload["text"]?.try(&.as_s?) || ""
        return if text.empty?
        Tmux.send_literal(name, text)
      when "key"
        key = normalize_key(payload["key"]?.try(&.as_s?) || "")
        Tmux.send_key(name, key) if key
      when "resize"
        cols = payload["cols"]?.try(&.as_i?) || 0
        rows = payload["rows"]?.try(&.as_i?) || 0
        return if cols < 40 || rows < 10
        Tmux.resize_window(name, cols, rows)
      end
    end

    private def normalize_key(key : String) : String?
      case key
      when "Enter"      then "Enter"
      when "Backspace"  then "BSpace"
      when "Tab"        then "Tab"
      when "Escape"     then "Escape"
      when "ArrowUp"    then "Up"
      when "ArrowDown"  then "Down"
      when "ArrowLeft"  then "Left"
      when "ArrowRight" then "Right"
      when "Delete"     then "Delete"
      when "Home"       then "Home"
      when "End"        then "End"
      when "PageUp"     then "PageUp"
      when "PageDown"   then "PageDown"
      when "CtrlC"      then "C-c"
      when "CtrlD"      then "C-d"
      when "CtrlZ"      then "C-z"
      else
        nil
      end
    end

    private def dashboard_page : String
      <<-HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>AIX Web</title>
          <style>
            :root {
              color-scheme: dark;
              --bg: #111827;
              --panel: #1f2937;
              --panel-soft: #273449;
              --border: #3d4f66;
              --text: #e5edf7;
              --muted: #9fb0c7;
              --accent: #7dd3fc;
              --danger: #fb7185;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              background: radial-gradient(circle at top, #1f3b57 0%, var(--bg) 45%);
              color: var(--text);
              font: 15px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            }
            main { width: 100%; margin: 0; padding: 28px 24px 56px; }
            header { display: flex; justify-content: space-between; gap: 16px; align-items: end; margin-bottom: 24px; }
            h1 { margin: 0; font-size: 32px; }
            p { margin: 6px 0 0; color: var(--muted); }
            .panel {
              background: rgba(31, 41, 55, 0.92);
              border: 1px solid var(--border);
              border-radius: 18px;
              padding: 16px;
              box-shadow: 0 18px 40px rgba(0, 0, 0, 0.28);
            }
            .toolbar {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              align-items: center;
            }
            .layout {
              display: flex;
              gap: 8px;
              align-items: center;
            }
            .layout-label {
              color: var(--muted);
              font-size: 13px;
            }
            form.add { display: grid; grid-template-columns: 1fr auto; gap: 12px; margin-bottom: 16px; }
            .roots { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 20px; }
            .roots .chip { display: inline-flex; align-items: center; gap: 8px; padding: 4px 10px; border-radius: 999px; background: #172233; font-size: 13px; }
            .roots .chip button { background: none; border: none; color: #8fa3bf; cursor: pointer; padding: 0; font-size: 15px; line-height: 1; }
            .roots .chip button:hover { color: #ff6b6b; }
            .roots .empty-roots { color: #8fa3bf; font-size: 13px; }
            input, button {
              border-radius: 12px;
              border: 1px solid var(--border);
              background: var(--panel-soft);
              color: var(--text);
              padding: 12px 14px;
              font: inherit;
            }
            button {
              cursor: pointer;
              transition: background 120ms ease, border-color 120ms ease;
            }
            button:hover { background: #334155; border-color: var(--accent); }
            button.danger:hover { border-color: var(--danger); }
            .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }
            .grid {
              display: grid;
              gap: 16px;
            }
            .grid.columns-2 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
            .grid.columns-3 { grid-template-columns: repeat(3, minmax(0, 1fr)); }
            .grid.columns-4 { grid-template-columns: repeat(4, minmax(0, 1fr)); }
            .card h2 { margin: 0; font-size: 18px; }
            .meta { margin-top: 8px; color: var(--muted); font-size: 13px; }
            .status { display: inline-block; margin-top: 12px; padding: 4px 8px; border-radius: 999px; background: #172233; }
            pre {
              margin: 14px 0 0;
              padding: 12px;
              min-height: 180px;
              overflow: auto;
              border-radius: 14px;
              border: 1px solid #314258;
              background: #0a1220;
              color: #d7e4f5;
              white-space: pre-wrap;
            }
            .empty {
              color: var(--muted);
              padding: 32px;
              text-align: center;
              border: 1px dashed var(--border);
              border-radius: 16px;
            }
            .message { margin-bottom: 16px; min-height: 24px; color: var(--accent); }
            .message.error { color: var(--danger); }
            button.active {
              background: #334155;
              border-color: var(--accent);
              color: #ffffff;
            }
            @media (max-width: 1180px) {
              .grid.columns-4 { grid-template-columns: repeat(3, minmax(0, 1fr)); }
            }
            @media (max-width: 960px) {
              .grid.columns-3,
              .grid.columns-4 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
            }
            @media (max-width: 760px) {
              form.add { grid-template-columns: 1fr; }
              header { display: block; }
              .grid.columns-2,
              .grid.columns-3,
              .grid.columns-4 { grid-template-columns: 1fr; }
            }
          </style>
        </head>
        <body>
          <main>
            <header>
              <div>
                <h1>AIX Web</h1>
                <p>Projects are discovered under your root paths — any directory containing a <code>.ai/</code> folder.</p>
              </div>
              <div class="toolbar">
                <div class="layout">
                  <span class="layout-label">Layout</span>
                  <button id="layout-2" type="button" data-columns="2">2 Col</button>
                  <button id="layout-3" type="button" data-columns="3">3 Col</button>
                  <button id="layout-4" type="button" data-columns="4">4 Col</button>
                </div>
                <button id="refresh" type="button">Refresh</button>
              </div>
            </header>

            <section class="panel">
              <div id="message" class="message"></div>
              <form id="add-form" class="add">
                <input id="root" name="root" placeholder="~/code  (root path scanned for .ai/ projects)" autocomplete="off">
                <button type="submit">Add Root</button>
              </form>
              <div id="roots" class="roots"></div>
              <div id="sessions" class="grid"></div>
            </section>
          </main>

          <script>
            const sessionsEl = document.getElementById("sessions");
            const rootsEl = document.getElementById("roots");
            const messageEl = document.getElementById("message");
            const addForm = document.getElementById("add-form");
            const refreshButton = document.getElementById("refresh");
            const layoutButtons = [...document.querySelectorAll("[data-columns]")];
            const storedColumns = localStorage.getItem("aix:web:columns") || "3";

            function escapeHtml(value) {
              return value
                .replaceAll("&", "&amp;")
                .replaceAll("<", "&lt;")
                .replaceAll(">", "&gt;")
                .replaceAll('"', "&quot;");
            }

            async function api(url, options = {}) {
              const response = await fetch(url, {
                headers: { "Content-Type": "application/json" },
                ...options,
              });
              const data = await response.json().catch(() => ({}));
              if (!response.ok) throw new Error(data.error || response.statusText);
              return data;
            }

            function flash(message, isError = false) {
              messageEl.textContent = message;
              messageEl.classList.toggle("error", isError);
            }

            function applyColumns(columns) {
              const normalized = ["2", "3", "4"].includes(columns) ? columns : "3";
              sessionsEl.classList.remove("columns-2", "columns-3", "columns-4");
              sessionsEl.classList.add(`columns-${normalized}`);
              layoutButtons.forEach((button) => {
                button.classList.toggle("active", button.dataset.columns === normalized);
              });
              localStorage.setItem("aix:web:columns", normalized);
            }

            function sessionCard(session) {
              const preview = session.preview && session.preview.trim() ? escapeHtml(session.preview) : "Session is not running.";
              const state = escapeHtml(session.state);
              const name = escapeHtml(session.name);
              const directory = escapeHtml(session.directory);

              return `
                <article class="panel card" data-name="${name}">
                  <h2>${name}</h2>
                  <div class="meta">${directory}</div>
                  <div class="status">${state}</div>
                  <pre>${preview}</pre>
                  <div class="actions">
                    <button type="button" data-action="open" data-name="${name}">Open</button>
                    <button type="button" data-action="start" data-name="${name}">Start</button>
                    <button type="button" data-action="resume" data-name="${name}">Resume</button>
                    <button type="button" data-action="stop" data-name="${name}">Stop</button>
                  </div>
                </article>
              `;
            }

            async function loadSessions() {
              const data = await api("/api/sessions");
              if (!data.sessions.length) {
                sessionsEl.innerHTML = '<div class="empty">No projects found. Add a root path above, then create a <code>.ai/</code> directory in each project.</div>';
                return;
              }
              sessionsEl.innerHTML = data.sessions.map(sessionCard).join("");
            }

            async function loadRoots() {
              const data = await api("/api/roots");
              if (!data.roots.length) {
                rootsEl.innerHTML = '<span class="empty-roots">No roots configured yet.</span>';
                return;
              }
              rootsEl.innerHTML = data.roots.map((root) => {
                const safe = escapeHtml(root);
                return `<span class="chip">${safe}<button type="button" data-root="${safe}" title="Remove root">×</button></span>`;
              }).join("");
            }

            async function reload() {
              await Promise.all([loadRoots(), loadSessions()]);
            }

            async function sessionAction(name, action, payload = {}) {
              const encoded = encodeURIComponent(name);
              if (action === "open") {
                window.location.href = `/sessions/${encoded}`;
                return;
              }

              await api(`/api/sessions/${encoded}/${action}`, {
                method: "POST",
                body: JSON.stringify(payload),
              });
              flash(`${name}: ${action} complete`);
              await loadSessions();
            }

            addForm.addEventListener("submit", async (event) => {
              event.preventDefault();
              const rootInput = document.getElementById("root");
              const path = rootInput.value.trim();
              if (!path) return;
              try {
                const data = await api("/api/roots", {
                  method: "POST",
                  body: JSON.stringify({ path }),
                });
                addForm.reset();
                flash(`Root added — ${data.count} project(s) discovered`);
                await reload();
              } catch (error) {
                flash(error.message, true);
              }
            });

            rootsEl.addEventListener("click", async (event) => {
              const button = event.target.closest("button[data-root]");
              if (!button) return;
              const path = button.dataset.root;
              if (!window.confirm(`Remove root ${path}?`)) return;
              try {
                await api("/api/roots", { method: "DELETE", body: JSON.stringify({ path }) });
                flash("Root removed");
                await reload();
              } catch (error) {
                flash(error.message, true);
              }
            });

            sessionsEl.addEventListener("click", async (event) => {
              const button = event.target.closest("button[data-action]");
              if (!button) return;

              const action = button.dataset.action;
              const name = button.dataset.name;
              try {
                if (action === "resume") {
                  await sessionAction(name, "start", { resume: true });
                } else {
                  await sessionAction(name, action);
                }
              } catch (error) {
                flash(error.message, true);
              }
            });

            refreshButton.addEventListener("click", async () => {
              try {
                const data = await api("/api/refresh", { method: "POST" });
                flash(`Rescanned — ${data.count} project(s)`);
                await reload();
              } catch (error) {
                flash(error.message, true);
              }
            });

            layoutButtons.forEach((button) => {
              button.addEventListener("click", () => applyColumns(button.dataset.columns));
            });

            applyColumns(storedColumns);
            reload().catch((error) => flash(error.message, true));
            setInterval(() => loadSessions().catch(() => {}), 3000);
          </script>
        </body>
      </html>
      HTML
    end

    private def session_page(name : String) : String
      escaped_name = HTML.escape(name)
      javascript_name = name.to_json

      <<-HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{escaped_name} · AIX Web</title>
          <style>
            :root {
              color-scheme: dark;
              --bg: #0f172a;
              --panel: #111827;
              --border: #334155;
              --text: #e2e8f0;
              --muted: #94a3b8;
              --accent: #7dd3fc;
              --danger: #fb7185;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              background: linear-gradient(180deg, #0b1221, #111827 40%, #0f172a);
              color: var(--text);
              font: 15px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            }
            main { max-width: 1280px; margin: 0 auto; padding: 24px 20px 40px; }
            .toolbar, .panel {
              border: 1px solid var(--border);
              background: rgba(17, 24, 39, 0.96);
              border-radius: 18px;
              box-shadow: 0 18px 40px rgba(0, 0, 0, 0.32);
            }
            .toolbar {
              padding: 16px;
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              align-items: center;
              margin-bottom: 16px;
            }
            .toolbar strong { font-size: 18px; }
            .toolbar .meta { color: var(--muted); margin-left: auto; }
            button, input {
              border-radius: 12px;
              border: 1px solid var(--border);
              background: #1e293b;
              color: var(--text);
              padding: 10px 12px;
              font: inherit;
            }
            button { cursor: pointer; }
            button:hover { border-color: var(--accent); }
            .danger:hover { border-color: var(--danger); }
            .panel { padding: 16px; }
            pre#pane {
              margin: 0;
              min-height: 62vh;
              max-height: 70vh;
              overflow: auto;
              padding: 16px;
              border-radius: 14px;
              border: 1px solid #223047;
              background: #020617;
              white-space: pre-wrap;
              outline: none;
            }
            .controls, .command {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              margin-top: 14px;
            }
            .command input {
              flex: 1;
              min-width: 240px;
            }
            .hint {
              margin-top: 12px;
              color: var(--muted);
            }
            @media (max-width: 760px) {
              .toolbar .meta { width: 100%; margin-left: 0; }
              pre#pane { min-height: 50vh; }
            }
          </style>
        </head>
        <body>
          <main>
            <section class="toolbar">
              <a href="/" style="color: var(--accent); text-decoration: none;">&larr; Projects</a>
              <strong>#{escaped_name}</strong>
              <button type="button" id="start">Start</button>
              <button type="button" id="resume">Resume</button>
              <button type="button" class="danger" id="stop">Stop</button>
              <div class="meta">Click the pane, then type. Use the command box for full lines.</div>
            </section>

            <section class="panel">
              <pre id="pane" tabindex="0">Connecting...</pre>
              <div class="controls">
                <button type="button" data-key="Enter">Enter</button>
                <button type="button" data-key="Tab">Tab</button>
                <button type="button" data-key="Backspace">Backspace</button>
                <button type="button" data-key="ArrowUp">Up</button>
                <button type="button" data-key="ArrowDown">Down</button>
                <button type="button" data-key="Escape">Esc</button>
                <button type="button" data-key="CtrlC">Ctrl-C</button>
              </div>
              <form id="command-form" class="command">
                <input id="command" autocomplete="off" placeholder="Send a full command line">
                <button type="submit">Send Line</button>
              </form>
              <div id="status" class="hint">Waiting for session state...</div>
            </section>
          </main>

          <script>
            const sessionName = #{javascript_name};
            const pane = document.getElementById("pane");
            const statusEl = document.getElementById("status");
            const commandForm = document.getElementById("command-form");
            const commandInput = document.getElementById("command");
            const protocol = location.protocol === "https:" ? "wss" : "ws";
            const socket = new WebSocket(`${protocol}://${location.host}/ws/sessions/${encodeURIComponent(sessionName)}`);

            function send(message) {
              if (socket.readyState === WebSocket.OPEN) {
                socket.send(JSON.stringify(message));
              }
            }

            function resizePane() {
              const cols = Math.max(40, Math.floor((pane.clientWidth - 24) / 8.4));
              const rows = Math.max(10, Math.floor((pane.clientHeight - 24) / 18));
              send({ type: "resize", cols, rows });
            }

            async function api(path, payload = {}) {
              const response = await fetch(path, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload),
              });
              const data = await response.json().catch(() => ({}));
              if (!response.ok) throw new Error(data.error || response.statusText);
              return data;
            }

            socket.addEventListener("open", () => {
              statusEl.textContent = "Connected";
              resizePane();
              pane.focus();
            });

            socket.addEventListener("message", (event) => {
              const payload = JSON.parse(event.data);
              if (payload.type === "error") {
                statusEl.textContent = payload.error;
                return;
              }

              pane.textContent = payload.text || "";
              statusEl.textContent = `${payload.state}${payload.running ? "" : " - session not running"}`;
              pane.scrollTop = pane.scrollHeight;
            });

            socket.addEventListener("close", () => {
              statusEl.textContent = "Disconnected";
            });

            commandForm.addEventListener("submit", (event) => {
              event.preventDefault();
              const text = commandInput.value;
              if (!text.trim()) return;
              send({ type: "command", text });
              commandInput.value = "";
              pane.focus();
            });

            document.querySelectorAll("[data-key]").forEach((button) => {
              button.addEventListener("click", () => {
                send({ type: "key", key: button.dataset.key });
                pane.focus();
              });
            });

            document.getElementById("start").addEventListener("click", async () => {
              try {
                await api(`/api/sessions/${encodeURIComponent(sessionName)}/start`);
                pane.focus();
              } catch (error) {
                statusEl.textContent = error.message;
              }
            });

            document.getElementById("resume").addEventListener("click", async () => {
              try {
                await api(`/api/sessions/${encodeURIComponent(sessionName)}/start`, { resume: true });
                pane.focus();
              } catch (error) {
                statusEl.textContent = error.message;
              }
            });

            document.getElementById("stop").addEventListener("click", async () => {
              try {
                await api(`/api/sessions/${encodeURIComponent(sessionName)}/stop`);
              } catch (error) {
                statusEl.textContent = error.message;
              }
            });

            pane.addEventListener("keydown", (event) => {
              if (document.activeElement === commandInput) return;

              if (event.ctrlKey && event.key === "c") {
                event.preventDefault();
                send({ type: "key", key: "CtrlC" });
                return;
              }

              if (event.ctrlKey && event.key === "d") {
                event.preventDefault();
                send({ type: "key", key: "CtrlD" });
                return;
              }

              const special = ["Enter", "Backspace", "Tab", "Escape", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Delete", "Home", "End", "PageUp", "PageDown"];
              if (special.includes(event.key)) {
                event.preventDefault();
                send({ type: "key", key: event.key });
                return;
              }

              if (!event.ctrlKey && !event.metaKey && event.key.length === 1) {
                event.preventDefault();
                send({ type: "input", text: event.key });
              }
            });

            pane.addEventListener("click", () => pane.focus());
            window.addEventListener("resize", resizePane);
          </script>
        </body>
      </html>
      HTML
    end
  end
end
