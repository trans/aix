module Aix
  # The web page (`aix --web`, at `/`): the agents on the left, the
  # selected agent's conversation in the middle, read from its transcript
  # and following it live (`Transcript`), and its project's files on the
  # right (`ProjectFiles`). Served as three files, so the page can forbid
  # any script but its own (`WebApp.security_headers`): the conversation's
  # HTML comes from markdown in safe mode, and everything else is set as
  # text.
  module WebPage
    HTML = <<-'HTML'
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>aix</title>
          <link rel="stylesheet" href="/app.css">
        </head>
        <body>
          <header>
            <span class="brand">aix</span>
            <span id="agent-name"></span>
            <span id="agent-info"></span>
            <span class="spacer"></span>
            <span id="actions"></span>
          </header>
          <div id="notice" hidden></div>
          <main>
            <nav id="agents-panel">
              <h2>Agents</h2>
              <ul id="agents"></ul>
            </nav>
            <section id="middle">
              <div class="tabs">
                <button id="conversation-tab" class="tab active">Conversation</button>
                <span id="file-tab-group" hidden>
                  <button id="file-tab" class="tab"></button><button id="file-close" class="close" title="Close the file">×</button>
                </span>
              </div>
              <div id="conversation" class="pane"></div>
              <div id="file" class="pane" hidden></div>
              <div id="composer">
                <div id="screen-strip" hidden>
                  <pre id="screen"></pre>
                  <div id="keys" class="keys"></div>
                </div>
                <div class="compose-row">
                  <textarea id="message" rows="3"></textarea>
                  <button id="send">Send</button>
                </div>
                <div class="compose-foot">
                  <span id="compose-hint"></span>
                  <button id="screen-toggle" class="link"></button>
                </div>
              </div>
            </section>
            <aside id="files-panel">
              <h2>Files</h2>
              <div id="files"></div>
            </aside>
          </main>
          <script src="/app.js"></script>
        </body>
      </html>
      HTML

    CSS = <<-'CSS'
      :root {
        color-scheme: dark;
        --bg: #111827;
        --panel: #172033;
        --raised: #1f2937;
        --border: #334155;
        --text: #e5edf7;
        --muted: #94a3b8;
        --accent: #7dd3fc;
        --you: #a78bfa;
        --ok: #4ade80;
        --warn: #fbbf24;
        --danger: #fb7185;
      }
      * { box-sizing: border-box; }
      html, body { height: 100%; }
      body {
        margin: 0; display: flex; flex-direction: column;
        background: var(--bg); color: var(--text);
        font: 15px/1.5 system-ui, sans-serif;
      }
      header {
        display: flex; align-items: center; gap: 0.75rem;
        padding: 0.5rem 1rem; border-bottom: 1px solid var(--border); background: var(--panel);
      }
      .brand { font-weight: 700; color: var(--accent); }
      #agent-name { font-weight: 600; }
      #agent-info { color: var(--muted); font-size: 0.9em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .spacer { flex: 1; }
      #actions { display: flex; gap: 0.5rem; }
      button, a.button {
        font: inherit; font-size: 0.9em; color: var(--text); background: var(--raised);
        border: 1px solid var(--border); border-radius: 6px; padding: 0.25rem 0.75rem;
        cursor: pointer; text-decoration: none;
      }
      button:hover, a.button:hover { border-color: var(--accent); }
      #notice { padding: 0.5rem 1rem; background: #3b1d2a; color: var(--danger); border-bottom: 1px solid var(--border); }
      main { flex: 1; min-height: 0; display: grid; grid-template-columns: 16rem minmax(0, 1fr) 23rem; grid-template-rows: minmax(0, 1fr); }
      nav, aside { min-height: 0; overflow: auto; background: var(--panel); }
      nav { border-right: 1px solid var(--border); }
      aside { border-left: 1px solid var(--border); }
      h2 { margin: 0; padding: 0.6rem 0.9rem; font-size: 0.75em; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
      #agents { list-style: none; margin: 0; padding: 0 0 1rem; }
      .agent { padding: 0.3rem 0.75rem; cursor: pointer; border-left: 3px solid transparent; }
      .agent:hover { background: var(--raised); }
      .agent.selected { background: var(--raised); border-left-color: var(--accent); }
      .agent .mark { display: inline-block; width: 1.2em; color: var(--muted); }
      .agent .mark.running { color: var(--ok); }
      .agent .mark.elsewhere { color: var(--warn); }
      .agent .title { margin-left: 1.2em; font-size: 0.8em; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      #middle { min-width: 0; min-height: 0; display: flex; flex-direction: column; }
      .tabs { display: flex; gap: 0.25rem; padding: 0.4rem 0.75rem 0; border-bottom: 1px solid var(--border); }
      .tab { border-radius: 6px 6px 0 0; border-bottom: none; color: var(--muted); }
      .tab.active { color: var(--text); background: var(--bg); border-color: var(--accent); }
      .close { border: none; background: none; padding: 0.25rem 0.4rem; color: var(--muted); }
      .pane { flex: 1; min-height: 0; overflow: auto; padding: 1rem 1.5rem 3rem; }
      /* The conversation, and a markdown file, in a column centred in the pane. */
      #conversation > *, #file > .markdown { max-width: 46rem; margin-left: auto; margin-right: auto; }
      .msg { margin-top: 0; margin-bottom: 1rem; }
      .msg.user { border-left: 3px solid var(--you); padding: 0.1rem 0 0.1rem 0.9rem; }
      .msg.user::before { content: "You"; display: block; font-size: 0.75em; font-weight: 600; color: var(--you); }
      .msg > :first-child, .markdown > :first-child { margin-top: 0; }
      .msg > :last-child { margin-bottom: 0; }
      pre, code { font-family: ui-monospace, "JetBrains Mono", monospace; font-size: 0.88em; }
      pre { background: var(--panel); border: 1px solid var(--border); border-radius: 6px; padding: 0.6rem 0.8rem; overflow: auto; }
      :not(pre) > code { background: var(--raised); border-radius: 4px; padding: 0.05rem 0.3rem; }
      a { color: var(--accent); }
      table { border-collapse: collapse; }
      th, td { border: 1px solid var(--border); padding: 0.25rem 0.6rem; }
      blockquote { margin-left: 0; padding-left: 0.9rem; border-left: 3px solid var(--border); color: var(--muted); }
      details.summary { margin-top: 0; margin-bottom: 1rem; color: var(--muted); font-style: italic; }
      details.summary > summary { cursor: pointer; }
      details.summary > .msg { font-style: normal; color: var(--text); margin-top: 0.6rem; padding-left: 1rem; border-left: 2px solid var(--border); }
      details.tool { margin-top: 0; margin-bottom: 0.5rem; font-size: 0.88em; color: var(--muted); }
      details.tool > summary { cursor: pointer; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      details.tool .tool-name { color: var(--accent); font-weight: 600; }
      details.tool.error .tool-name { color: var(--danger); }
      pre.tool-result.error { border-color: var(--danger); }
      .note { color: var(--muted); font-style: italic; margin-top: 0; margin-bottom: 1rem; }
      .tree { list-style: none; margin: 0; padding: 0 0 0 1rem; }
      #files > .tree { font-size: 1rem; padding: 0 0.5rem 1rem; }
      .tree .label { cursor: pointer; display: block; padding: 0.1rem 0.4rem; border-radius: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .tree .label:hover { background: var(--raised); }
      .tree .dir > .label { color: var(--accent); }
      .tree .dir:not(.open) > ul { display: none; }
      .tree .label.current { background: var(--raised); outline: 1px solid var(--accent); }
      .error { color: var(--danger); }
      #composer { border-top: 1px solid var(--border); padding: 0.6rem 1.5rem 0.4rem; background: var(--panel); }
      #composer > * { max-width: 46rem; margin-left: auto; margin-right: auto; }
      #screen { max-height: 18rem; margin-top: 0; margin-bottom: 0.5rem; font-size: 0.8em; line-height: 1.3; background: var(--bg); }
      .keys { display: flex; flex-wrap: wrap; gap: 0.3rem; margin-bottom: 0.5rem; }
      .keys button { min-width: 2.2rem; padding: 0.15rem 0.5rem; }
      .compose-row { display: flex; gap: 0.5rem; }
      textarea {
        flex: 1; resize: vertical; min-height: 3.4rem; max-height: 40vh;
        font: inherit; color: var(--text); background: var(--bg);
        border: 1px solid var(--border); border-radius: 6px; padding: 0.5rem 0.6rem;
      }
      textarea:focus { outline: none; border-color: var(--accent); }
      #send { align-self: stretch; min-width: 5rem; }
      .compose-foot { display: flex; justify-content: space-between; gap: 1rem; min-height: 1.4em; margin-top: 0.25rem; font-size: 0.8em; color: var(--muted); }
      button.link { background: none; border: none; padding: 0; color: var(--accent); font-size: inherit; }
      button:disabled { opacity: 0.45; cursor: default; }
      CSS

    JS = <<-'JS'
      "use strict";
      const $ = (selector) => document.querySelector(selector);
      const state = {
        agents: [], selected: null, socket: null, tools: new Map(), title: "",
        // The agent's input (`Sender.screen`), and whether its screen is shown when it needn't be.
        screen: { mode: "off", waiting: false, busy: false, screen: "" }, showScreen: false,
      };

      // An element, with its attributes and its children (strings become text).
      function el(tag, attributes = {}, ...children) {
        const element = document.createElement(tag);
        for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, value);
        element.append(...children);
        return element;
      }

      async function getJSON(url, options) {
        const response = await fetch(url, options);
        const data = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(data.error || response.statusText);
        return data;
      }

      function notice(message) {
        const box = $("#notice");
        box.textContent = message || "";
        box.hidden = !message;
      }

      const agentURL = (name, rest) => `/api/agents/${encodeURIComponent(name)}${rest}`;
      const selectedAgent = () => state.agents.find((agent) => agent.name === state.selected);

      async function loadAgents() {
        try {
          state.agents = (await getJSON("/api/agents")).agents;
          renderAgents();
          if (!state.selected) {
            const wanted = decodeURIComponent(location.hash.slice(1));
            const first = state.agents.find((agent) => agent.name === wanted) ||
              state.agents.find((agent) => agent.running) || state.agents[0];
            if (first) select(first.name);
          } else {
            renderHeader();
          }
        } catch (error) {
          notice(`Couldn't list the agents: ${error.message}`);
        }
      }

      function renderAgents() {
        const list = $("#agents");
        list.replaceChildren();
        for (const agent of state.agents) {
          const item = el("li", { class: "agent" + (agent.name === state.selected ? " selected" : ""), title: agent.directory });
          item.style.paddingLeft = `${0.75 + agent.level}rem`;
          const kind = agent.running ? " running" : agent.mark === "◐" ? " elsewhere" : "";
          item.append(el("span", { class: "mark" + kind }, agent.mark), el("span", { class: "name" }, agent.name));
          if (agent.title) item.append(el("div", { class: "title" }, agent.title));
          item.addEventListener("click", () => select(agent.name));
          list.append(item);
        }
      }

      function renderHeader() {
        const agent = selectedAgent();
        $("#agent-name").textContent = agent ? `@${agent.name}` : "";
        const states = { cold: "not started", stopped: "stopped" };
        const info = agent ? [agent.harness, agent.running ? "running" : (states[agent.state] || agent.state), agent.title || state.title] : [];
        $("#agent-info").textContent = info.filter(Boolean).join(" · ");
        const actions = $("#actions");
        actions.replaceChildren();
        if (!agent) return;
        if (agent.running) {
          actions.append(button("Stop", () => stop(agent.name)));
        } else {
          actions.append(button("Start", () => start(agent.name, true), "Resume its last conversation"),
            button("New", () => start(agent.name, false), "Start a new conversation"));
        }
        actions.append(el("a", { class: "button", href: `/sessions/${encodeURIComponent(agent.name)}`, target: "_blank",
          title: "Its terminal (a snapshot view, for now)" }, "Terminal"));
        renderComposer();
      }

      // The message box: a message, sent whole, when the agent's input box
      // is empty; else keys, with its screen shown, for a menu or a prompt.
      function renderComposer() {
        const agent = selectedAgent();
        const input = state.screen;
        const running = Boolean(agent && agent.running && input.mode !== "off");
        const keys = input.mode === "keys";
        const message = $("#message");
        message.disabled = !running;
        $("#send").disabled = !running;
        $("#send").textContent = keys ? "Type" : "Send";
        message.placeholder = !running ? "Start the agent to write to it."
          : keys ? "Typed into it as keys, without Enter: an answer's number, or your own words. Then Enter."
          : `Write to @${agent.name}. Ctrl+Enter sends.`;
        $("#compose-hint").textContent = !running ? ""
          : input.waiting ? "It's waiting on your answer: use the keys above, or type your answer, then Enter."
          : keys ? "Its input box isn't empty, or it's showing something else: see its screen above."
          : input.busy ? "It's working: a message now waits for its turn to end." : "";
        $("#screen-strip").hidden = !(running && (keys || state.showScreen));
        const screen = $("#screen");
        screen.textContent = input.screen;
        screen.scrollTop = screen.scrollHeight;
        const toggle = $("#screen-toggle");
        toggle.hidden = !running || keys;
        toggle.textContent = state.showScreen ? "Hide its screen" : "Show its screen";
      }

      async function post(name, what, payload) {
        try {
          await getJSON(agentURL(name, what), {
            method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload),
          });
          notice("");
          return true;
        } catch (error) {
          notice(error.message);
          return false;
        }
      }

      async function send() {
        const agent = selectedAgent();
        const message = $("#message");
        if (!agent || message.disabled) return;
        const keys = state.screen.mode === "keys";
        const text = message.value;
        if (!(keys ? text : text.trim())) return;
        // Kept unless it went: a refusal leaves the message to send again.
        if (await post(agent.name, keys ? "/type" : "/send", { text })) message.value = "";
        message.focus();
      }

      const KEYS = [["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["↑", "Up"], ["↓", "Down"], ["←", "Left"], ["→", "Right"],
        ["Enter", "Enter"], ["Esc", "Escape"], ["Tab", "Tab"], ["⇧Tab", "ShiftTab"], ["Space", "Space"], ["⌫", "Backspace"]];
      for (const [label, key] of KEYS) {
        $("#keys").append(button(label, () => {
          const agent = selectedAgent();
          if (agent) post(agent.name, "/key", { key });
        }, key));
      }

      function button(label, action, title = "") {
        const element = el("button", { title }, label);
        element.addEventListener("click", action);
        return element;
      }

      async function start(name, resume) {
        try {
          await getJSON(`/api/sessions/${encodeURIComponent(name)}/start`, {
            method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ resume }),
          });
          notice("");
          await loadAgents();
        } catch (error) {
          notice(error.message);
        }
      }

      async function stop(name) {
        if (!confirm(`Stop @${name}'s agent?`)) return;
        try {
          await getJSON(`/api/sessions/${encodeURIComponent(name)}/stop`, { method: "POST" });
          notice("");
          await loadAgents();
        } catch (error) {
          notice(error.message);
        }
      }

      function select(name) {
        state.selected = name;
        state.title = "";
        state.screen = { mode: "off", waiting: false, busy: false, screen: "" };
        state.showScreen = false;
        history.replaceState(null, "", `#${encodeURIComponent(name)}`);
        notice("");
        renderAgents();
        renderHeader();
        closeFile();
        openConversation(name);
        loadTree(name);
      }

      // The conversation, from a WebSocket that sends its entries as the
      // agent's transcript grows.
      function openConversation(name) {
        if (state.socket) {
          state.socket.onclose = null;
          state.socket.close();
        }
        clearConversation();
        const socket = new WebSocket(`ws://${location.host}/ws/agents/${encodeURIComponent(name)}/conversation`);
        state.socket = socket;
        socket.onmessage = (event) => {
          const message = JSON.parse(event.data);
          if (message.type === "reset") {
            clearConversation();
            if (message.note) addNote(message.note);
          } else if (message.type === "entries") {
            addEntries(message.entries);
          } else if (message.type === "screen") {
            state.screen = message.state;
            renderComposer();
          }
        };
        socket.onclose = () => {
          setTimeout(() => { if (state.socket === socket && state.selected === name) openConversation(name); }, 3000);
        };
      }

      function clearConversation() {
        state.tools.clear();
        $("#conversation").replaceChildren();
      }

      function addNote(text) {
        $("#conversation").append(el("p", { class: "note" }, text));
      }

      function addEntries(entries) {
        const box = $("#conversation");
        const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
        for (const entry of entries) {
          switch (entry.kind) {
            case "user":
            case "assistant": {
              const message = el("div", { class: `msg ${entry.kind}` });
              message.innerHTML = entry.html; // markdown, rendered by aix in safe mode
              box.append(message);
              break;
            }
            case "tool": {
              const details = el("details", { class: "tool" },
                el("summary", {}, el("span", { class: "tool-name" }, entry.name), " ", entry.summary),
                el("pre", { class: "tool-input" }, entry.input));
              state.tools.set(entry.id, details);
              box.append(details);
              break;
            }
            case "result": {
              const result = el("pre", { class: "tool-result" + (entry.error ? " error" : "") }, entry.text || "(no output)");
              const details = state.tools.get(entry.id);
              if (details) {
                details.append(result);
                if (entry.error) details.classList.add("error");
              } else {
                box.append(result);
              }
              break;
            }
            case "summary": {
              const summary = el("div", { class: "msg summary" });
              summary.innerHTML = entry.html; // markdown, rendered by aix in safe mode
              box.append(el("details", { class: "summary" },
                el("summary", {}, "Claude Code's summary of the conversation before"), summary));
              break;
            }
            case "title":
              state.title = entry.text;
              renderHeader();
              break;
            case "note":
              addNote(entry.text);
              break;
          }
        }
        if (atBottom) box.scrollTop = box.scrollHeight;
      }

      // The project's files: a folder's entries are fetched when it's opened.
      async function loadTree(name) {
        const files = $("#files");
        files.replaceChildren();
        const tree = await folder(name, "");
        if (state.selected === name) files.replaceChildren(tree);
      }

      async function folder(name, path) {
        const list = el("ul", { class: "tree" });
        try {
          const { items } = await getJSON(agentURL(name, `/files?path=${encodeURIComponent(path)}`));
          for (const item of items) {
            const entry = el("li", { class: item.dir ? "dir" : "file" });
            const label = el("span", { class: "label", title: item.path }, (item.dir ? "▸ " : "") + item.name);
            entry.append(label);
            if (item.dir) {
              label.addEventListener("click", async () => {
                const open = entry.classList.toggle("open");
                label.textContent = (open ? "▾ " : "▸ ") + item.name;
                if (open && !entry.querySelector("ul")) entry.append(await folder(name, item.path));
              });
            } else {
              label.addEventListener("click", () => openFile(name, item.path, label));
            }
            list.append(entry);
          }
        } catch (error) {
          list.append(el("li", { class: "error" }, error.message));
        }
        return list;
      }

      async function openFile(name, path, label) {
        try {
          const shown = await getJSON(agentURL(name, `/file?path=${encodeURIComponent(path)}`));
          const view = $("#file");
          view.replaceChildren();
          if (shown.kind === "markdown") {
            const body = el("div", { class: "markdown msg" });
            body.innerHTML = shown.html; // rendered by aix in safe mode
            view.append(body);
          } else if (shown.kind === "text") {
            view.append(el("pre", {}, shown.text));
          } else {
            view.append(el("p", { class: "note" }, shown.kind === "binary" ? "A binary file: not shown." : `Too large to show (${shown.size} bytes).`));
          }
          document.querySelectorAll(".tree .label.current").forEach((current) => current.classList.remove("current"));
          label.classList.add("current");
          $("#file-tab").textContent = path;
          $("#file-tab-group").hidden = false;
          showPane("file");
        } catch (error) {
          notice(`Couldn't open ${path}: ${error.message}`);
        }
      }

      function closeFile() {
        $("#file-tab-group").hidden = true;
        $("#file").replaceChildren();
        document.querySelectorAll(".tree .label.current").forEach((current) => current.classList.remove("current"));
        showPane("conversation");
      }

      function showPane(which) {
        $("#conversation").hidden = which !== "conversation";
        $("#file").hidden = which !== "file";
        $("#conversation-tab").classList.toggle("active", which === "conversation");
        $("#file-tab").classList.toggle("active", which === "file");
      }

      $("#conversation-tab").addEventListener("click", () => showPane("conversation"));
      $("#file-tab").addEventListener("click", () => showPane("file"));
      $("#file-close").addEventListener("click", closeFile);
      $("#send").addEventListener("click", send);
      $("#message").addEventListener("keydown", (event) => {
        if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
          event.preventDefault();
          send();
        }
      });
      $("#screen-toggle").addEventListener("click", () => {
        state.showScreen = !state.showScreen;
        renderComposer();
      });

      loadAgents();
      setInterval(loadAgents, 5000);
      JS
  end
end
