import { DurableObject } from "cloudflare:workers";

// Text messages are tiny, but a 29-second browser voice recording is sent as
// Base64 JSON and is normally around 120 KB. Keep a firm per-player ceiling
// while allowing that intended feature.
const MAX_PLAYER_MSG = 512 * 1024;
const MAX_PLAYERS = 40;

export class Room extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(
      '{"type":"heartbeat"}', '{"type":"heartbeat_ack"}'
    ));
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("Expected WebSocket", { status: 426 });
    const url = new URL(request.url);
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    if (url.pathname === "/ws/host") {
      const token = url.searchParams.get("token") || "";
      if (token.length < 16) return new Response("Bad token", { status: 403 });
      const saved = await this.ctx.storage.get("token");
      if (saved && saved !== token) return new Response("Wrong token", { status: 403 });
      if (!saved) await this.ctx.storage.put("token", token);
      for (const old of this.ctx.getWebSockets("host")) { try { old.close(1012, "replaced"); } catch {} }
      this.ctx.acceptWebSocket(server, ["host"]);
      server.serializeAttachment({ role: "host" });
      return new Response(null, { status: 101, webSocket: client });
    }
    const host = this.liveHost();
    if (!host || this.ctx.getWebSockets("player").length >= MAX_PLAYERS) {
      server.accept();
      server.send(JSON.stringify({ type: "relay_error", message: host ? "This room is full." : "The Storyteller is not online for this room yet." }));
      server.close(1013, "unavailable");
      return new Response(null, { status: 101, webSocket: client });
    }
    const id = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
    this.ctx.acceptWebSocket(server, ["player", id]);
    server.serializeAttachment({ role: "player", id });
    host.send(JSON.stringify({ t: "open", c: id }));
    return new Response(null, { status: 101, webSocket: client });
  }

  liveHost(except) { return this.ctx.getWebSockets("host").find((s) => s !== except && s.readyState === WebSocket.OPEN); }

  async webSocketMessage(ws, message) {
    if (typeof message !== "string") return;
    const att = ws.deserializeAttachment() || {};
    if (att.role === "player") {
      if (message.length > MAX_PLAYER_MSG) {
        ws.send(JSON.stringify({
          type: "relay_error",
          message: "This voice message is too large. Please record a shorter message.",
        }));
        return;
      }
      const host = this.liveHost();
      if (host) host.send(JSON.stringify({ t: "msg", c: att.id, d: message }));
      return;
    }
    if (att.role === "host") {
      let m; try { m = JSON.parse(message); } catch { return; }
      if (m.t === "to" && typeof m.d === "string") this.ctx.getWebSockets(m.c)[0]?.send(m.d);
      else if (m.t === "all" && typeof m.d === "string") for (const p of this.ctx.getWebSockets("player")) p.send(m.d);
      else if (m.t === "kick") { const p = this.ctx.getWebSockets(m.c)[0]; if (p) { try { p.close(1000, "removed"); } catch {} } }
    }
  }

  gone(ws) {
    const att = ws.deserializeAttachment() || {};
    try { ws.close(1000, "closing"); } catch {}
    if (att.role === "player") this.liveHost()?.send(JSON.stringify({ t: "close", c: att.id }));
    else if (att.role === "host" && !this.liveHost(ws)) for (const p of this.ctx.getWebSockets("player")) {
      try { p.send(JSON.stringify({ type: "relay_error", message: "Lost connection to the Storyteller. Reconnecting…" })); p.close(1013, "host offline"); } catch {}
    }
  }
  async webSocketClose(ws) { this.gone(ws); }
  async webSocketError(ws) { this.gone(ws); }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/ws/host" || url.pathname === "/ws/player") {
      const room = (url.searchParams.get("room") || "").toLowerCase();
      if (!/^[a-z0-9]{8,32}$/.test(room)) return new Response("Bad room code", { status: 400 });
      return env.ROOM.getByName(room).fetch(request);
    }
    if (url.pathname === "/play" || url.pathname.startsWith("/play/")) return env.ASSETS.fetch(new Request(new URL("/", url), request));
    return env.ASSETS.fetch(request);
  }
};
