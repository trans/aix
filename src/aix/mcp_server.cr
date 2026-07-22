require "json"
require "./control"

module Aix
  # Minimal MCP (Model Context Protocol) server over stdio, exposing the Aix
  # control surface as tools. A Leader/orchestrator harness (Claude Code,
  # codex, ...) configured with this server can drive Aix sessions
  # programmatically: list / start / stop / send / peek.
  #
  # Transport: newline-delimited JSON-RPC 2.0. stdin carries requests, stdout
  # carries responses (protocol only — nothing else may be written there).
  # All diagnostics go to stderr.
  class MCPServer
    SERVER_NAME      = "aix-control"
    DEFAULT_PROTOCOL = "2024-11-05"

    def initialize
      @control = Control.new
    end

    def run
      log "ready — #{@control.manager.sessions.size} project(s) discovered"
      while line = STDIN.gets
        line = line.strip
        next if line.empty?

        message = begin
          JSON.parse(line)
        rescue ex
          respond_error(nil, -32700, "Parse error: #{ex.message}")
          next
        end

        dispatch(message)
      end
    end

    private def dispatch(message : JSON::Any)
      id = message["id"]?
      method = message["method"]?.try(&.as_s)

      unless method
        respond_error(id, -32600, "Invalid Request: missing method") if id
        return
      end

      case method
      when "initialize"
        handle_initialize(id, message)
      when "tools/list"
        respond(id, {tools: tool_definitions})
      when "tools/call"
        handle_tools_call(id, message)
      when "ping"
        respond(id, {} of String => JSON::Any)
      when .starts_with?("notifications/")
        # Notifications carry no id and expect no response.
      else
        respond_error(id, -32601, "Method not found: #{method}") if id
      end
    end

    private def handle_initialize(id, message : JSON::Any)
      requested = message["params"]?.try(&.["protocolVersion"]?).try(&.as_s)
      respond(id, {
        protocolVersion: requested || DEFAULT_PROTOCOL,
        capabilities:    {tools: {} of String => JSON::Any},
        serverInfo:      {name: SERVER_NAME, version: Aix::VERSION},
      })
    end

    private def handle_tools_call(id, message : JSON::Any)
      params = message["params"]?
      name = params.try(&.["name"]?).try(&.as_s)
      args = params.try(&.["arguments"]?) || JSON.parse("{}")

      unless name
        return respond_error(id, -32602, "Invalid params: missing tool name")
      end

      begin
        text = call_tool(name, args)
        respond(id, {content: [{type: "text", text: text}], isError: false})
      rescue ex
        log "tool '#{name}' failed: #{ex.message}"
        respond(id, {content: [{type: "text", text: "Error: #{ex.message}"}], isError: true})
      end
    end

    private def call_tool(name : String, args : JSON::Any) : String
      case name
      when "list_projects"
        @control.list.to_json
      when "list_roots"
        @control.roots.to_json
      when "add_root"
        @control.add_root(arg_string(args, "path")).to_json
      when "refresh"
        @control.refresh.to_json
      when "status"
        @control.status(arg_string(args, "name")).to_json
      when "start"
        @control.start(arg_string(args, "name"), arg_string_array(args, "args")).to_json
      when "stop"
        @control.stop(arg_string(args, "name")).to_json
      when "send"
        @control.send_text(arg_string(args, "name"), arg_string(args, "text")).to_json
      when "peek"
        @control.peek(arg_string(args, "name"), args["lines"]?.try(&.as_i?))
      else
        raise "Unknown tool: #{name}"
      end
    end

    private def arg_string(args : JSON::Any, key : String) : String
      value = args[key]?.try(&.as_s?)
      raise "Missing required argument: #{key}" if value.nil? || value.empty?
      value
    end

    private def arg_string_array(args : JSON::Any, key : String) : Array(String)
      arr = args[key]?.try(&.as_a?)
      return [] of String unless arr
      arr.compact_map(&.as_s?)
    end

    private def respond(id, result)
      write({jsonrpc: "2.0", id: id, result: result})
    end

    private def respond_error(id, code : Int32, message : String)
      write({jsonrpc: "2.0", id: id, error: {code: code, message: message}})
    end

    private def write(payload)
      STDOUT.puts(payload.to_json)
      STDOUT.flush
    end

    private def log(message : String)
      STDERR.puts("[aix-mcp] #{message}")
      STDERR.flush
    end

    private def tool_definitions : JSON::Any
      JSON.parse(TOOLS_JSON)
    end

    TOOLS_JSON = <<-JSON
    [
      {
        "name": "list_projects",
        "description": "List all discovered AIX projects with their live state (running, cold, or stopped). A project is any directory containing a .ai/ folder under a configured root.",
        "inputSchema": { "type": "object", "properties": {} }
      },
      {
        "name": "status",
        "description": "Get the state of a single AIX project by name.",
        "inputSchema": {
          "type": "object",
          "properties": { "name": { "type": "string", "description": "Project name" } },
          "required": ["name"]
        }
      },
      {
        "name": "start",
        "description": "Start the AI harness (e.g. Claude Code) in a project's tmux window. Fails if it is already running.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "Project name" },
            "args": { "type": "array", "items": { "type": "string" }, "description": "Optional extra args passed to the harness" }
          },
          "required": ["name"]
        }
      },
      {
        "name": "stop",
        "description": "Stop a running session's tmux window. The project remains discoverable and can be started again.",
        "inputSchema": {
          "type": "object",
          "properties": { "name": { "type": "string", "description": "Project name" } },
          "required": ["name"]
        }
      },
      {
        "name": "send",
        "description": "Send a line of text (followed by Enter) to a running session — e.g. a prompt or command for the agent in that project.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "Project name" },
            "text": { "type": "string", "description": "Text to send" }
          },
          "required": ["name", "text"]
        }
      },
      {
        "name": "peek",
        "description": "Capture the visible terminal output of a running session. Use this to read what the agent in that project has produced.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "Project name" },
            "lines": { "type": "integer", "description": "Optional: scroll back this many lines of history" }
          },
          "required": ["name"]
        }
      },
      {
        "name": "list_roots",
        "description": "List the configured root paths (scanned for projects) and the scan depth.",
        "inputSchema": { "type": "object", "properties": {} }
      },
      {
        "name": "add_root",
        "description": "Add a root path to scan for projects, then re-discover.",
        "inputSchema": {
          "type": "object",
          "properties": { "path": { "type": "string", "description": "Directory path (may use ~)" } },
          "required": ["path"]
        }
      },
      {
        "name": "refresh",
        "description": "Re-scan configured roots for projects (picks up newly created .ai/ directories).",
        "inputSchema": { "type": "object", "properties": {} }
      }
    ]
    JSON
  end
end
