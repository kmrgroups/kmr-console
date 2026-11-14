/* KMR Connect - the live part: signalling, peer links, the meeting room, the recorder and the remote-desktop viewer.
   Nothing here needs a paid server: the video goes directly between the computers (WebRTC), and the "hello / offer / answer"
   notes are passed through the platform's own realtime channel (Supabase Realtime) that all KMR apps already use.
   With no database connection (?demo=1) the same notes pass between browser tabs of the same computer, so the screens can be tried without sign-in. */
(function () {
  "use strict";
  const CFG = window.COMPANY_CONFIG || {};
  /* free public STUN servers find the way between two computers; a company TURN server (optional, company-config.js "turn") is used when a network blocks direct video */
  const ICE = [{ urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478"] }].concat(CFG.turn || []);
  const rid = () => Array.from(crypto.getRandomValues(new Uint8Array(8)), (b) => b.toString(16).padStart(2, "0")).join("");

  /* ---------- signalling: one named channel, small JSON notes ---------- */
  function Sig(name, sb, onmsg, onstatus) {
    const me = rid(); let ch = null, bc = null;
    const pass = (p) => { if (p && p.from !== me && (!p.to || p.to === me)) { try { onmsg(p); } catch (e) { console.error(e); } } };
    if (sb) {
      ch = sb.channel(name, { config: { broadcast: { self: false } } });
      ch.on("broadcast", { event: "m" }, ({ payload }) => pass(payload));
      ch.subscribe((s) => { if (onstatus) onstatus(s === "SUBSCRIBED" ? "ready" : (s === "CHANNEL_ERROR" || s === "TIMED_OUT") ? "error" : s); });
    } else {
      bc = new BroadcastChannel(name); bc.onmessage = (e) => pass(e.data); setTimeout(() => onstatus && onstatus("ready"), 0);
    }
    return {
      id: me,
      send(m) { m = JSON.parse(JSON.stringify(m)); m.from = me; if (ch) return ch.send({ type: "broadcast", event: "m", payload: m }); bc.postMessage(m); },
      close() { try { if (ch) sb.removeChannel(ch); if (bc) bc.close(); } catch (e) { /* ignore */ } }
    };
  }

  /* ---------- one link to one other computer ---------- */
  /* o.tracks: tracks to send ({audio, video} or arrays); o.dir: "sendrecv" | "recvonly" | "sendonly"; o.channel: name of a data channel to open (offering side) */
  function Link(sig, remote, o) {
    o = o || {};
    const pc = new RTCPeerConnection({ iceServers: ICE }), pend = []; let dc = null, closed = false;
    const stream = new MediaStream();
    pc.onicecandidate = (e) => { if (e.candidate) sig.send({ to: remote, t: "ice", d: e.candidate }); };
    pc.ontrack = (e) => { stream.addTrack(e.track); if (o.onTrack) o.onTrack(e.track, stream); };
    pc.onconnectionstatechange = () => { if (!closed && o.onState) o.onState(pc.connectionState); };
    pc.ondatachannel = (e) => { dc = e.channel; wire(); };
    function wire() {
      dc.binaryType = "arraybuffer";
      dc.onopen = () => o.onOpen && o.onOpen(dc);
      dc.onclose = () => o.onClose && o.onClose();
      dc.onmessage = (e) => o.onData && o.onData(e.data);
    }
    const kinds = () => pc.getTransceivers().filter((t) => t.receiver && t.receiver.track);
    function attach() {   // put our tracks on the matching transceivers
      kinds().forEach((t) => {
        const k = t.receiver.track.kind, mine = o.tracks && o.tracks[k];
        t.direction = o.dir || "sendrecv";
        if (t.direction !== "recvonly" && mine) t.sender.replaceTrack(mine).catch(() => { });
      });
    }
    async function flush() { while (pend.length) { try { await pc.addIceCandidate(pend.shift()); } catch (e) { /* late candidate */ } } }
    return {
      pc, stream, get channel() { return dc; },
      async offer() {
        pc.addTransceiver("audio", { direction: o.dir || "sendrecv" }); pc.addTransceiver("video", { direction: o.dir || "sendrecv" });
        attach();
        if (o.channel) { dc = pc.createDataChannel(o.channel, { ordered: true }); wire(); }
        await pc.setLocalDescription(await pc.createOffer());
        sig.send({ to: remote, t: "offer", d: pc.localDescription });
      },
      async signal(m) {
        if (closed) return;
        if (m.t === "offer") { await pc.setRemoteDescription(m.d); attach(); await flush(); await pc.setLocalDescription(await pc.createAnswer()); sig.send({ to: remote, t: "answer", d: pc.localDescription }); }
        else if (m.t === "answer") { await pc.setRemoteDescription(m.d); await flush(); }
        else if (m.t === "ice") { if (pc.remoteDescription) { try { await pc.addIceCandidate(m.d); } catch (e) { /* ignore */ } } else pend.push(m.d); }
      },
      swapTrack(kind, track) { pc.getSenders().forEach((s) => { if (s.track ? s.track.kind === kind : false) s.replaceTrack(track).catch(() => { }); else if (!s.track && pc.getTransceivers().some((t) => t.sender === s && t.receiver.track && t.receiver.track.kind === kind)) s.replaceTrack(track).catch(() => { }); }); },
      send(v) { if (dc && dc.readyState === "open") { dc.send(v); return true; } return false; },
      close() { closed = true; try { if (dc) dc.close(); pc.close(); } catch (e) { /* ignore */ } }
    };
  }

  /* ---------- the meeting room (everybody connected to everybody, good for about 8 people) ---------- */
  /* o: { sb, key, user:{name,email}, stream, onPeer(id, peer), onGone(id), onData(id, obj), onTrack(id, track), onStatus(text) } */
  function Room(o) {
    const peers = new Map(); let hello = null, sig = null;
    const tracks = () => o.stream ? { audio: o.stream.getAudioTracks()[0] || null, video: o.stream.getVideoTracks()[0] || null } : {};
    function addPeer(id, info) {
      if (peers.has(id)) { Object.assign(peers.get(id).info, info); return peers.get(id); }
      const p = { id, info: info || {}, link: null, open: false };
      p.link = Link(sig, id, {
        tracks: tracks(), dir: o.stream ? "sendrecv" : "recvonly", channel: "room",
        onTrack: (t) => o.onTrack && o.onTrack(id, t, p.link.stream),
        onOpen: () => { p.open = true; o.onPeer && o.onPeer(id, p); },
        onData: (d) => { try { o.onData && o.onData(id, JSON.parse(d), p); } catch (e) { /* not ours */ } },
        onState: (s) => { if (s === "failed" || s === "closed") drop(id); }
      });
      peers.set(id, p); return p;
    }
    function drop(id) { const p = peers.get(id); if (!p) return; peers.delete(id); p.link.close(); o.onGone && o.onGone(id, p); }
    function onSig(m) {
      if (m.t === "hello" || m.t === "hello2") {
        if (peers.has(m.from)) return;
        const p = addPeer(m.from, m.u);
        if (m.t === "hello") sig.send({ to: m.from, t: "hello2", u: o.user });
        if (sig.id < m.from) p.link.offer().catch((e) => o.onStatus && o.onStatus("Could not start the video link: " + e.message));
      } else if (m.t === "bye") drop(m.from);
      else { const p = peers.get(m.from); if (p) p.link.signal(m).catch(() => { }); }
    }
    sig = Sig("cnm-" + o.key, o.sb, onSig, (s) => {
      if (s === "ready") { sig.send({ t: "hello", u: o.user }); o.onStatus && o.onStatus("Connected. Waiting for others to join…"); hello = setInterval(() => { if (peers.size === 0) sig.send({ t: "hello", u: o.user }); }, 8000); }
      else if (s === "error") o.onStatus && o.onStatus("The platform's realtime service did not answer. Check the internet connection and open the room again.");
    });
    return {
      id: sig.id, peers,
      data(obj) { const s = JSON.stringify(obj); peers.forEach((p) => p.link.send(s)); },
      setTrack(kind, track) { peers.forEach((p) => p.link.swapTrack(kind, track)); },
      leave() { try { sig.send({ t: "bye" }); } catch (e) { /* ignore */ } clearInterval(hello); [...peers.keys()].forEach(drop); setTimeout(() => sig.close(), 300); }
    };
  }

  /* ---------- the recorder: all voices mixed + a picture of the room, saved in parts of 10 minutes ---------- */
  function Recorder(o) {   // o: { tiles(): [{el, name}], video: true|false, onPart(blob, seconds, mime), onError(msg) }
    const AC = window.AudioContext || window.webkitAudioContext; let ac = null, dest = null, cv = null, ctx = null, mr = null, timer = null, draw = null, started = 0, partStart = 0, on = false, mime = "";
    const pick = () => { const c = o.video ? ["video/webm;codecs=vp8,opus", "video/webm"] : ["audio/webm;codecs=opus", "audio/webm"]; return c.find((x) => window.MediaRecorder && MediaRecorder.isTypeSupported(x)) || ""; };
    function paint() {
      const t = o.tiles().filter((x) => x.el && x.el.videoWidth), W = cv.width, H = cv.height; ctx.fillStyle = "#0b1020"; ctx.fillRect(0, 0, W, H);
      if (!t.length) return; const cols = Math.ceil(Math.sqrt(t.length)), rows = Math.ceil(t.length / cols), w = W / cols, h = H / rows;
      t.forEach((x, i) => {
        const cx = (i % cols) * w, cy = Math.floor(i / cols) * h, r = Math.min(w / x.el.videoWidth, h / x.el.videoHeight), dw = x.el.videoWidth * r, dh = x.el.videoHeight * r;
        try { ctx.drawImage(x.el, cx + (w - dw) / 2, cy + (h - dh) / 2, dw, dh); } catch (e) { /* frame not ready */ }
        ctx.fillStyle = "#000a"; ctx.fillRect(cx + 6, cy + h - 26, Math.min(w - 12, 220), 20); ctx.fillStyle = "#fff"; ctx.font = "13px sans-serif"; ctx.fillText(x.name || "", cx + 12, cy + h - 11);
      });
    }
    function begin() {
      const tr = [...dest.stream.getAudioTracks()]; if (o.video) tr.push(...cv.captureStream(12).getVideoTracks());
      mime = pick(); const chunks = [];
      mr = new MediaRecorder(new MediaStream(tr), Object.assign(mime ? { mimeType: mime } : {}, o.video ? { videoBitsPerSecond: 500000, audioBitsPerSecond: 48000 } : { audioBitsPerSecond: 32000 }));
      mr.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };
      mr.onstop = () => { const secs = Math.round((Date.now() - partStart) / 1000); if (chunks.length) o.onPart(new Blob(chunks, { type: mime || "video/webm" }), secs, mime || "video/webm"); };
      partStart = Date.now(); mr.start(5000);
    }
    return {
      get on() { return on; }, get seconds() { return started ? Math.round((Date.now() - started) / 1000) : 0; },
      addTrack(track) { if (!ac || track.kind !== "audio") return; try { ac.createMediaStreamSource(new MediaStream([track])).connect(dest); } catch (e) { /* ignore */ } },
      start(audioTracks) {
        if (!window.MediaRecorder) { o.onError("This browser cannot record. Use Chrome or Edge."); return false; }
        ac = new AC(); ac.resume(); dest = ac.createMediaStreamDestination(); (audioTracks || []).forEach((t) => this.addTrack(t));
        if (o.video) { cv = document.createElement("canvas"); cv.width = 1280; cv.height = 720; ctx = cv.getContext("2d"); draw = setInterval(paint, 1000 / 12); }
        started = Date.now(); on = true; begin();
        timer = setInterval(() => { if (mr && mr.state === "recording") { const old = mr; begin(); old.stop(); } }, 10 * 60 * 1000);   // a new, separately playable file every 10 minutes (free storage takes files up to 50 MB)
        return true;
      },
      stop() { on = false; clearInterval(timer); clearInterval(draw); try { if (mr && mr.state !== "inactive") mr.stop(); } catch (e) { /* ignore */ } setTimeout(() => { try { ac.close(); } catch (e) { /* ignore */ } }, 1500); started = 0; }
    };
  }

  /* ---------- the remote-desktop viewer (the person who works on the other computer) ---------- */
  /* o: { sb, secret, who, video: <video>, onStatus(text, kind), onFiles(msg), onConnected() } */
  function Viewer(o) {
    let link = null, host = null, hello = null, tries = 0, ctl = null; const waiters = new Map(); let seq = 1;
    const sig = Sig("cnr-" + o.secret, o.sb, onSig, (s) => {
      if (s === "ready") { ask(); hello = setInterval(() => { if (host) return; if (++tries > 12) { clearInterval(hello); o.onStatus("This device did not answer. It may be switched off, asleep or without internet. Check the green dot on the device list.", "bad"); return; } ask(); }, 3500); o.onStatus("Calling the device…", "wait"); }
      else if (s === "error") o.onStatus("The platform's realtime service did not answer. Check the internet connection.", "bad");
    });
    const ask = () => sig.send({ t: "viewer", who: o.who });
    function onSig(m) {
      if (m.t === "busy") { o.onStatus("Someone else is already connected to this device.", "bad"); return; }
      if (m.t === "host" && !host) { host = m.from; clearInterval(hello); start(m); return; }
      if (link && m.from === host) link.signal(m).catch(() => { });
    }
    async function start(h) {
      o.onStatus("Device found" + (h.name ? ": " + h.name : "") + ". Opening the screen…", "wait");
      link = Link(sig, host, {
        dir: "recvonly", channel: "ctl",
        onTrack: (t, st) => { if (t.kind === "video") { o.video.srcObject = st; o.video.play().catch(() => { }); } },
        onOpen: (dc) => { ctl = dc; o.onStatus("Connected", "ok"); o.onConnected && o.onConnected(h); },
        onClose: () => o.onStatus("The connection ended.", "bad"),
        onState: (s) => { if (s === "failed") o.onStatus("The connection failed. Press Connect again.", "bad"); },
        onData: (d) => { try { const m = JSON.parse(d); if (m.id && waiters.has(m.id)) { waiters.get(m.id)(m); waiters.delete(m.id); } else if (o.onEvent) o.onEvent(m); } catch (e) { /* ignore */ } }
      });
      try { await link.offer(); } catch (e) { o.onStatus("Could not start the link: " + e.message, "bad"); }
    }
    return {
      send(obj) { return link && link.send(JSON.stringify(obj)); },
      /* ask the agent on the device to do something and wait for the answer (files, programs, clipboard) */
      call(obj, ms) {
        return new Promise((res, rej) => {
          const id = "r" + seq++; obj.id = id; const t = setTimeout(() => { waiters.delete(id); rej(new Error("The device did not answer in time.")); }, ms || 30000);
          waiters.set(id, (m) => { clearTimeout(t); m.error ? rej(new Error(m.error)) : res(m); });
          if (!link || !link.send(JSON.stringify(obj))) { clearTimeout(t); waiters.delete(id); rej(new Error("Not connected.")); }
        });
      },
      get connected() { return !!ctl && ctl.readyState === "open"; },
      close() { clearInterval(hello); try { if (link) link.close(); } catch (e) { /* ignore */ } sig.close(); }
    };
  }

  window.CNRTC = { Sig, Link, Room, Recorder, Viewer, ICE, rid };
})();
