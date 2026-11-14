/* KMR Connect - screens: Dashboard, Meetings (video room / Teams / Google Meet, recording, minutes), Remote devices (screen, mouse, keyboard, files, programs). */
(function () {
  "use strict";
  const { $, esc, today, say, call } = QP, LG = window.MOMLang, R = window.CNRTC, DEMO = QP.DEMO;
  const S = { load: null, det: null, room: null, tiles: new Map(), local: null, camTrack: null, share: null, sr: null, segs: [], seen: new Set(), queue: [], rec: null, recOn: false, recPeers: false, mid: "", saver: null, parts: 0, ext: null, v: null, sess: null };
  const ed = () => QP.canEdit, adm = () => QP.ctx && (QP.ctx.role === "admin" || QP.ctx.is_staff);
  const email = () => (QP.ctx && QP.ctx.email) || "demo@example.com";
  const myName = () => email().split("@")[0];
  const open = (h) => { $("#mb").innerHTML = h; $("#m").classList.add("on"); }, closeM = () => $("#m").classList.remove("on");
  $("#m").addEventListener("click", (e) => { if (e.target.id === "m") closeM(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$(".rv")) closeM(); });
  const V = (id) => { const e = $("#" + id); return e ? (e.type === "checkbox" ? e.checked : e.value) : ""; };
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : "c" + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
  const hashGo = () => { const m = location.hash.match(/go=([a-z]+)/); return m ? m[1] : "std"; };
  const hashM = () => { const m = location.hash.match(/[&?]m=([0-9a-zA-Z-]+)/); return m ? m[1] : ""; };
  const dt = (v) => (v ? new Date(v).toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: true }) : "—");
  const tm = (v) => (v ? new Date(v).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: true }) : "");
  const dur = (a, b) => { if (!a) return "—"; const s = Math.max(0, Math.round(((b ? new Date(b) : new Date()) - new Date(a)) / 1000)); return s >= 3600 ? Math.floor(s / 3600) + " h " + Math.floor((s % 3600) / 60) + " min" : Math.floor(s / 60) + " min " + (s % 60) + " s"; };
  const ago = (v) => { if (!v) return "never"; const s = Math.round((Date.now() - new Date(v)) / 1000); return s < 90 ? "just now" : s < 3600 ? Math.round(s / 60) + " min ago" : s < 86400 ? Math.round(s / 3600) + " h ago" : dt(v); };
  const langOpts = (sel) => LG.list.map((l) => `<option value="${l.tag}"${l.tag === sel ? " selected" : ""}>${esc(LG.label(l))}${l.voice ? "" : " (typing only)"}</option>`).join("");
  const PROV = { kmr: "KMR video room", teams: "Microsoft Teams", meet: "Google Meet" };
  const stChip = (s) => `<span class="chip ${({ planned: "b", live: "r", ended: "g" })[s] || "x"}">${esc(({ planned: "Planned", live: "Live now", ended: "Ended" })[s] || s)}</span>`;
  const lockedF = (k) => window.KMRLock && !KMRLock.has(k);
  const ico = (t) => `<span aria-hidden="true">${t}</span>`;

  async function loadAll() { S.load = await call("kmr_cn_load"); }

  /* ================= router ================= */
  async function route() {
    let go = hashGo();
    if (window.KMRLock && KMRLock.locked(go)) { KMRLock.dialog(go); go = "std"; history.replaceState(null, "", location.pathname + location.search + "#go=std"); }
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("on", t.dataset.t === go));
    ["std", "dash", "meet", "dev"].forEach((s) => $("#" + s).classList.toggle("hide", s !== go));
    if (go === "std") { KMRStd.draw($("#std"), "connect"); return; }
    try {
      if (S.room && !(go === "meet" && hashM() === S.mid)) { say("You are still in a meeting. Open it from the Meetings list, or press Leave first."); history.replaceState(null, "", location.pathname + location.search + "#go=meet&m=" + S.mid); go = "meet"; document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("on", t.dataset.t === go)); ["std", "dash", "meet", "dev"].forEach((s) => $("#" + s).classList.toggle("hide", s !== go)); return; }
      await loadAll();
      if (go === "dash") drawDash();
      else if (go === "dev") drawDev();
      else { const id = hashM(); if (id) await openMeeting(id); else drawList(); }
    } catch (e) { say(e.message); }
  }
  document.addEventListener("click", (e) => { const a = e.target.closest('a[href^="#go="]'); if (!a || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return; e.preventDefault(); history.replaceState(null, "", location.pathname + location.search + a.getAttribute("href")); route(); });
  window.addEventListener("hashchange", route);
  const go = (h) => { history.replaceState(null, "", location.pathname + location.search + "#" + h); route(); window.scrollTo(0, 0); };
  window.addEventListener("beforeunload", (e) => { if (S.room || S.recOn || S.v) { e.preventDefault(); e.returnValue = ""; } });

  /* ================= dashboard ================= */
  function drawDash() {
    const L = S.load, ym = today().slice(0, 7), M = L.meetings, D = L.devices, SS = L.sessions;
    const onl = D.filter((d) => d.online).length;
    $("#dash").innerHTML = `<div class="kpis">
      <div class="kpi" style="--c:var(--g)"><span>Devices online</span><b>${onl} / ${D.length}</b></div>
      <div class="kpi"><span>Remote sessions this month</span><b>${SS.filter((s) => String(s.started_at).slice(0, 7) === ym).length}</b></div>
      <div class="kpi" style="--c:var(--b2)"><span>Meetings this month</span><b>${M.filter((m) => String(m.scheduled_at || "").slice(0, 7) === ym).length}</b></div>
      <div class="kpi" style="--c:var(--a)"><span>Meetings recorded</span><b>${M.filter((m) => +m.recordings > 0).length}</b></div>
      <div class="kpi" style="--c:var(--r)"><span>Live now</span><b>${M.filter((m) => m.status === "live").length}</b></div></div>
      <div class="guide">Start here: add a laptop under <a href="#go=dev">Remote devices</a>, or plan a meeting under <a href="#go=meet">Meetings</a>.</div>
      <h3>Next meetings</h3>${M.filter((m) => m.status !== "ended").slice(0, 6).length ? `<table><thead><tr><th>S.No</th><th>Meeting no.</th><th>Title</th><th>When</th><th>Where</th><th>Status</th></tr></thead><tbody>${M.filter((m) => m.status !== "ended").slice(0, 6).map((m, i) => `<tr><td>${i + 1}</td><td>${esc(m.meeting_no)}</td><td><a href="#go=meet&m=${m.id}">${esc(m.title)}</a></td><td>${dt(m.scheduled_at)}</td><td>${PROV[m.provider]}</td><td>${stChip(m.status)}</td></tr>`).join("")}</tbody></table>` : '<div class="empty">No planned meetings.</div>'}
      <h3>Latest remote sessions</h3>${SS.length ? sessTable(SS.slice(0, 6)) : '<div class="empty">No remote session yet.</div>'}`;
  }
  const sessTable = (rows) => `<table><thead><tr><th>S.No</th><th>Device</th><th>Worked by</th><th>Started</th><th>Time</th><th>Note</th></tr></thead><tbody>${rows.map((s, i) => `<tr><td>${i + 1}</td><td>${esc(s.device_name || "")}</td><td>${esc(s.started_by)}</td><td>${dt(s.started_at)}</td><td>${s.ended_at ? dur(s.started_at, s.ended_at) : '<span class="chip a">open</span>'}</td><td>${esc(s.note || "")}</td></tr>`).join("")}</tbody></table>`;

  /* ================= meetings list + form ================= */
  function drawList() {
    const M = S.load.meetings;
    $("#meet").innerHTML = `<div class="row"><h3 class="grow" style="margin:0">Meetings</h3>${ed() ? '<button class="btn" id="nm">+ New meeting</button>' : ""}</div>
      <div class="guide">Plan a meeting, then press <b>Open</b> on the day. Choose the free KMR video room, or paste a Microsoft Teams or Google Meet link. Spoken words are typed out in each person’s own language, and one button sends them to Minutes Of Meetings.</div>
      ${M.length ? `<table><thead><tr><th>S.No</th><th>Meeting no.</th><th>Title</th><th>When</th><th>Where</th><th>Status</th><th>Typed lines</th><th>Recordings</th><th></th></tr></thead><tbody>${M.map((m, i) => `<tr><td>${i + 1}</td><td>${esc(m.meeting_no)}</td><td>${esc(m.title)}</td><td>${dt(m.scheduled_at)}</td><td>${PROV[m.provider]}</td><td>${stChip(m.status)}</td><td class="n">${m.lines}</td><td class="n">${m.recordings}</td><td><a class="btn s" href="#go=meet&m=${m.id}">Open</a></td></tr>`).join("")}</tbody></table>` : '<div class="empty">No meeting yet.<br>Press “+ New meeting”.</div>'}`;
    const b = $("#nm"); if (b) b.onclick = () => meetForm();
  }
  function meetForm(m) {
    const ppl = S.load.people || [], sel = new Set((m && m.attendees || []).map((a) => a.email));
    const at = m && m.scheduled_at ? new Date(new Date(m.scheduled_at) - new Date().getTimezoneOffset() * 6e4).toISOString().slice(0, 16) : new Date(Date.now() + 36e5 - new Date().getTimezoneOffset() * 6e4).toISOString().slice(0, 16);
    open(`<h3>${m ? "Change meeting" : "New meeting"}</h3><div class="frm">
      <div style="grid-column:1/-1"><label class="lbl">Meeting title</label><input id="f_t" value="${esc(m ? m.title : "")}" placeholder="e.g. Customer quality review"></div>
      <div><label class="lbl">Date and time</label><input id="f_d" type="datetime-local" value="${at}"></div>
      <div><label class="lbl">Main language spoken</label><select id="f_l">${langOpts(m ? m.language : "en-IN")}</select></div>
      <div><label class="lbl">Where</label><select id="f_p"><option value="kmr">KMR video room (free, inside this app)</option><option value="teams">Microsoft Teams link</option><option value="meet">Google Meet link</option></select></div>
      <div id="f_uw" class="hide"><label class="lbl">Meeting link (paste it here)</label><input id="f_u" value="${esc(m && m.ext_url || "")}" placeholder="https://…"><div class="note"><a id="f_mk" target="_blank" rel="noopener">Create a new meeting</a>, then copy its link and paste it above.</div></div>
      <div style="grid-column:1/-1"><label class="lbl">Who should attend</label><div>${ppl.map((p) => `<label class="pill"><input type="checkbox" class="f_a" value="${esc(p.email)}" ${sel.has(p.email) ? "checked" : ""} style="width:auto"> ${esc(p.email)}</label>`).join("") || '<span class="mut">No company users yet.</span>'}</div></div>
      <div style="grid-column:1/-1"><label class="lbl">Agenda (optional)</label><textarea id="f_g" rows="3">${esc(m && m.agenda || "")}</textarea></div></div>
      <div class="row" style="margin-top:12px"><button class="btn" id="f_s">Save</button><button class="btn o" id="f_c">Cancel</button></div>`);
    if (m) $("#f_p").value = m.provider;
    const sync = () => { const p = V("f_p"); $("#f_uw").classList.toggle("hide", p === "kmr"); const a = $("#f_mk"); a.href = p === "teams" ? "https://teams.microsoft.com/l/meeting/new?subject=" + encodeURIComponent(V("f_t") || "Meeting") : "https://meet.google.com/new"; a.textContent = p === "teams" ? "Create a new Teams meeting" : "Create a new Google Meet"; };
    $("#f_p").onchange = sync; sync(); $("#f_c").onclick = closeM;
    $("#f_s").onclick = async () => {
      try {
        const att = [...document.querySelectorAll(".f_a:checked")].map((x) => ({ email: x.value }));
        const r = await call("kmr_cn_meeting_save", { p: { id: m && m.id, title: V("f_t"), scheduled_at: new Date(V("f_d")).toISOString(), language: V("f_l"), provider: V("f_p"), ext_url: V("f_u"), attendees: att, agenda: V("f_g") } });
        closeM(); say("Saved " + r.meeting_no, true); go("go=meet&m=" + r.id);
      } catch (e) { alert(e.message); }
    };
  }

  /* ================= one meeting ================= */
  async function openMeeting(id) {
    S.det = await call("kmr_cn_meeting_get", { p_id: id }); S.mid = id;
    if (!S.room && !S.ext) { S.segs = (S.det.segments || []).map((s) => Object.assign({}, s)); S.seen = new Set(S.segs.map((s) => s.client_id)); }
    drawMeeting();
  }
  const mt = () => S.det.meeting;
  function drawMeeting() {
    const m = mt(), live = !!(S.room || S.ext), ended = m.status === "ended", recLocked = lockedF("connect.recording-and-minutes");
    $("#meet").innerHTML = `<div class="row"><a href="#go=meet" class="btn o s">← All meetings</a><h3 class="grow" style="margin:0">${esc(m.meeting_no)} · ${esc(m.title)}</h3>${stChip(m.status)}${ed() && !ended && !live ? '<button class="btn o s" id="me">Change</button>' : ""}${adm() && !live ? '<button class="btn r s" id="mx">Delete</button>' : ""}</div>
      <div class="kv card"><div><span>When</span><b>${dt(m.scheduled_at)}</b></div><div><span>Where</span><b>${PROV[m.provider]}</b></div><div><span>Language</span><b>${esc((LG.byTag(m.language) || {}).name || m.language)}</b></div><div><span>Attendees</span><b>${(m.attendees || []).map((a) => esc(a.email)).join(", ") || "—"}</b></div><div><span>Started</span><b>${m.started_at ? dt(m.started_at) : "—"}</b></div>${m.ended_at ? `<div><span>Time</span><b>${dur(m.started_at, m.ended_at)}</b></div>` : ""}</div>
      ${m.agenda ? `<div class="card"><h3>Agenda</h3><div style="white-space:pre-wrap">${esc(m.agenda)}</div></div>` : ""}
      ${!ended && !live ? `<div class="row">${m.provider === "kmr" ? '<button class="btn" id="mj">Join the video room</button>' : `<a class="btn" id="mo" href="${esc(m.ext_url || "#")}" target="_blank" rel="noopener">Open ${PROV[m.provider]}</a><button class="btn o" id="mj" ${recLocked ? "disabled" : ""}>Record and type the minutes here</button>`}</div>${m.provider !== "kmr" && !m.ext_url ? '<div class="msg">No meeting link is saved yet. Press “Change” and paste the link.</div>' : ""}${m.provider !== "kmr" ? '<div class="note">For Teams and Google Meet the minutes here are typed from your microphone. To also record what others say, tick “capture the meeting tab sound” when asked.</div>' : ""}` : ""}
      <div id="live"></div>
      <div id="tr"></div>
      <div id="rc"></div>`;
    const b = $("#me"); if (b) b.onclick = () => meetForm(m);
    const x = $("#mx"); if (x) x.onclick = async () => { if (!confirm("Delete this meeting from the list?")) return; try { await call("kmr_cn_meeting_void", { p_id: m.id }); go("go=meet"); } catch (e) { alert(e.message); } };
    const j = $("#mj"); if (j) j.onclick = () => (m.provider === "kmr" ? joinRoom() : startExt());
    if (S.room) drawRoomUI(); else if (S.ext) drawExtUI();
    drawTranscript(); drawRecs();
  }

  /* ---- transcript, recordings, minutes ---- */
  function drawTranscript() {
    const m = mt(), el = $("#tr"); if (!el) return;
    const lines = S.segs.slice().sort((a, b) => new Date(a.spoken_at) - new Date(b.spoken_at));
    const can = ed() && !(S.room || S.ext) && lines.length && !lockedF("connect.recording-and-minutes");
    el.innerHTML = `<div class="row" style="margin-top:12px"><h3 class="grow" style="margin:0">What was said (typed in each person’s language)</h3>${lines.length ? '<button class="btn o s" id="tdl">Download text</button>' : ""}${can ? `<button class="btn s" id="tmom">${m.mom_id ? "Open the minutes" : "Send to Minutes Of Meetings"}</button>` : ""}</div>
      <div class="tr" id="trb">${lines.length ? lines.map((s) => `<p><small>${tm(s.spoken_at)} · ${esc(s.speaker || "")} · ${esc((LG.byTag(s.lang) || {}).name || s.lang || "")}</small><br>${esc(s.text)}</p>`).join("") : '<span class="mut">Nothing typed yet.</span>'}</div>`;
    const tb = $("#trb"); if (tb && (S.room || S.ext)) tb.scrollTop = tb.scrollHeight;
    const d = $("#tdl"); if (d) d.onclick = () => { const t = lines.map((s) => `[${tm(s.spoken_at)}] ${s.speaker || ""}: ${s.text}`).join("\n"), a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([t], { type: "text/plain" })); a.download = m.meeting_no + "-text.txt"; a.click(); };
    const k = $("#tmom"); if (k) k.onclick = async () => { try { const r = await call("kmr_cn_to_mom", { p_id: m.id }); m.mom_id = r.mom_id; if (QP.appHref) location.href = QP.appHref("mom", { hash: "go=meet&m=" + r.mom_id }); } catch (e) { alert(e.message); } };
  }
  function drawRecs() {
    const el = $("#rc"); if (!el) return; const R2 = (S.det.recordings || []);
    if (!R2.length) { el.innerHTML = ""; return; }
    el.innerHTML = `<h3 style="margin-top:14px">Recordings</h3><table><thead><tr><th>S.No</th><th>Saved</th><th>Length</th><th>Size</th><th>By</th><th></th></tr></thead><tbody>${R2.map((r, i) => `<tr><td>${i + 1}</td><td>${dt(r.created_at)}</td><td>${Math.floor((r.seconds || 0) / 60)} min ${(r.seconds || 0) % 60} s</td><td>${((r.bytes || 0) / 1048576).toFixed(1)} MB</td><td>${esc(r.created_by || "")}</td><td><button class="btn s" data-p="${r.id}">Play</button> <button class="btn o s" data-d="${r.id}">Download</button>${adm() ? ` <button class="btn r s" data-x="${r.id}">Delete</button>` : ""}</td></tr>`).join("")}</tbody></table><div id="rp"></div>`;
    const url = async (r) => { if (r.url) return r.url; const { data, error } = await QP.sb.storage.from("kmr-recordings").createSignedUrl(r.path, 3600); if (error) throw new Error(error.message); return data.signedUrl; };
    el.querySelectorAll("[data-p]").forEach((b) => (b.onclick = async () => { try { const r = R2.find((x) => x.id === b.dataset.p), u = await url(r), vid = /^video/.test(r.mime || "video"); $("#rp").innerHTML = `<${vid ? "video" : "audio"} controls autoplay src="${u}" style="width:100%;max-height:420px;margin-top:8px"></${vid ? "video" : "audio"}>`; } catch (e) { alert(e.message); } }));
    el.querySelectorAll("[data-d]").forEach((b) => (b.onclick = async () => { try { const r = R2.find((x) => x.id === b.dataset.d), a = document.createElement("a"); a.href = await url(r); a.download = mt().meeting_no + ".webm"; a.target = "_blank"; a.click(); } catch (e) { alert(e.message); } }));
    el.querySelectorAll("[data-x]").forEach((b) => (b.onclick = async () => { if (!confirm("Delete this recording for ever?")) return; try { const pth = await call("kmr_cn_rec_delete", { p_id: b.dataset.x }); if (pth && !DEMO) await QP.sb.storage.from("kmr-recordings").remove([pth]); S.det = await call("kmr_cn_meeting_get", { p_id: mt().id }); drawRecs(); } catch (e) { alert(e.message); } }));
  }

  /* ---- typing the spoken words (each person on their own device) ---- */
  const addLine = (s, mine) => {
    if (S.seen.has(s.client_id)) return; S.seen.add(s.client_id); S.segs.push(s); drawTranscript();
    if (mine) { S.queue.push(s); if (S.room) S.room.data({ t: "line", s }); }
  };
  async function flushLines() {
    if (!S.queue.length) return; const q = S.queue.splice(0, 100);
    try { await call("kmr_cn_seg_save", { p: { meeting_id: mt().id, segs: q } }); } catch (e) { S.queue.unshift(...q); say(e.message); }
  }
  function startTyping(lang) {
    stopTyping();
    if (!LG.supported) { say("Typing the spoken words needs Chrome, Edge or Safari."); return; }
    S.sr = LG.Recorder({ langs: [lang], onfinal: (r) => { if (r.text) addLine({ client_id: uid(), speaker: myName(), lang: r.lang, text: r.text, spoken_at: new Date().toISOString() }, true); }, oninterim: (r) => { const e = $("#iv"); if (e) e.textContent = r.text || ""; }, onerror: (e) => say(e.message) });
    S.sr.start(); if (!S.saver) S.saver = setInterval(flushLines, 6000);
  }
  function stopTyping() { if (S.sr) { S.sr.stop(); S.sr = null; } const e = $("#iv"); if (e) e.textContent = ""; }

  /* ---- recording ---- */
  async function uploadPart(blob, secs, mime) {
    const m = mt(); S.parts++;
    try {
      if (DEMO) { const u = URL.createObjectURL(blob); S.det.recordings.push({ id: uid(), path: "demo", url: u, mime, bytes: blob.size, seconds: secs, created_at: new Date().toISOString(), created_by: email() }); drawRecs(); say("Recording part saved (sample mode keeps it only in this tab).", true); return; }
      const path = `${QP.ctx.cid}/${m.id}/${Date.now()}-${S.parts}.webm`;
      const up = await QP.sb.storage.from("kmr-recordings").upload(path, blob, { contentType: mime });
      if (up.error) throw new Error(up.error.message + (/exceed|size/i.test(up.error.message) ? " (free storage takes files up to 50 MB)" : ""));
      await call("kmr_cn_rec_add", { p: { meeting_id: m.id, path, mime, bytes: blob.size, seconds: secs } });
      S.det = await call("kmr_cn_meeting_get", { p_id: m.id }); drawRecs(); say("Recording saved.", true);
    } catch (e) { say("The recording could not be saved: " + e.message); const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = m.meeting_no + "-part" + S.parts + ".webm"; a.click(); }
  }
  function startRec(withVideo) {
    if (lockedF("connect.recording-and-minutes")) { KMRLock.dialog && KMRLock.show && KMRLock.show("connect.recording-and-minutes"); return; }
    const audio = []; if (S.local) audio.push(...S.local.getAudioTracks()); if (S.extAudio) audio.push(...S.extAudio);
    S.tiles.forEach((t) => { if (!t.mine && t.stream) audio.push(...t.stream.getAudioTracks()); });
    S.rec = R.Recorder({ video: withVideo, tiles: () => [...S.tiles.values()].map((t) => ({ el: t.video, name: t.name })), onPart: uploadPart, onError: say });
    if (S.rec.start(audio)) { S.recOn = true; if (S.room) S.room.data({ t: "rec", on: true }); if (S.room) drawRoomUI(); else drawExtUI(); }
  }
  function stopRec() { if (S.rec) S.rec.stop(); S.rec = null; S.recOn = false; if (S.room) S.room.data({ t: "rec", on: false }); }

  /* ---- the video room ---- */
  async function joinRoom() {
    const m = mt(); let stream = null;
    try { stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true }, video: { width: 640, height: 360 } }); }
    catch (e) { try { stream = await navigator.mediaDevices.getUserMedia({ audio: true }); say("No camera found or allowed: you join with voice only."); } catch (e2) { say("The microphone and camera are blocked. You will only see and hear others. Allow them in the browser address bar to speak."); } }
    S.local = stream; S.camTrack = stream && stream.getVideoTracks()[0] || null;
    try { if (m.status === "planned" && ed()) { S.det.meeting = await call("kmr_cn_meeting_state", { p_id: m.id, p_state: "live" }); } } catch (e) { say(e.message); }
    S.tiles.clear(); addTile("me", myName() + " (you)", stream, true);
    S.room = R.Room({
      sb: QP.sb, key: S.det.room || m.id, user: { name: myName(), email: email() }, stream,
      onPeer: (id, p) => { const e = $("#rst"); if (e) e.textContent = "In the room: " + (S.room.peers.size + 1); },
      onTrack: (id, t, st) => { const p = S.room.peers.get(id); addTile(id, (p && p.info && p.info.name) || "Guest", st, false); if (S.rec && t.kind === "audio") S.rec.addTrack(t); },
      onGone: (id) => { removeTile(id); const e = $("#rst"); if (e) e.textContent = "In the room: " + (S.room ? S.room.peers.size + 1 : 1); },
      onData: (id, d) => { if (d.t === "line" && d.s) addLine(d.s, false); else if (d.t === "chat") chatAdd(d.n, d.x); else if (d.t === "rec") { const e = $("#rcn"); if (e) e.classList.toggle("hide", !d.on); } },
      onStatus: (t) => { const e = $("#rst"); if (e) e.textContent = t; }
    });
    drawMeeting();
  }
  function addTile(id, name, stream, mine) {
    let t = S.tiles.get(id);
    if (!t) { t = { id, name, mine, stream, video: document.createElement("video") }; t.video.autoplay = true; t.video.playsInline = true; t.video.muted = !!mine; S.tiles.set(id, t); }
    t.name = name; t.stream = stream; if (t.video.srcObject !== stream) t.video.srcObject = stream; t.video.play().catch(() => { });
    layoutTiles();
  }
  function removeTile(id) { S.tiles.delete(id); layoutTiles(); }
  function layoutTiles() {
    const g = $("#vg"); if (!g) return; g.innerHTML = "";
    S.tiles.forEach((t) => { const d = document.createElement("div"); d.className = "vtile"; d.append(t.video); const b = document.createElement("b"); b.textContent = t.name; d.append(b); g.append(d); });
  }
  function chatAdd(n, x) { const c = $("#chat"); if (!c) return; const p = document.createElement("p"); p.innerHTML = `<b>${esc(n)}:</b> ${esc(x)}`; c.append(p); c.scrollTop = c.scrollHeight; }
  function drawRoomUI() {
    const m = mt(), on = (id) => S.local && S.local.getTracks().find((t) => t.kind === id && t.enabled);
    $("#live").innerHTML = `<div class="vp ${S.recOn ? "rec" : ""}"><div class="row"><b id="rst">In the room: ${S.room.peers.size + 1}</b><span class="chip r ${S.recOn ? "" : "hide"}" id="rcn"><span class="dot"></span>Recording</span><span class="mut grow" style="text-align:right">Share this page’s meeting with colleagues: they open Meetings → ${esc(m.meeting_no)}.</span></div>
      <div class="vgrid" id="vg"></div>
      <div class="ctl"><button class="btn o s ${on("audio") ? "" : "r"}" id="c_mic">${on("audio") ? "Mute" : "Unmute"}</button><button class="btn o s ${on("video") ? "" : "r"}" id="c_cam" ${S.camTrack ? "" : "disabled"}>${on("video") ? "Camera off" : "Camera on"}</button>
        <button class="btn o s ${S.share ? "on" : ""}" id="c_sh">${S.share ? "Stop sharing" : "Share my screen"}</button>
        ${ed() && !lockedF("connect.recording-and-minutes") ? (S.recOn ? '<button class="btn r s" id="c_rs">Stop recording</button>' : '<button class="btn s" id="c_r1">Record with video</button><button class="btn o s" id="c_r2">Record voice only</button>') : ""}
        <select id="c_l" style="width:auto">${langOpts(S.sr ? S.sr.lang : m.language)}</select><button class="btn o s ${S.sr ? "on" : ""}" id="c_ty">${S.sr ? "Stop typing my words" : "Type my words"}</button>
        <span style="flex:1"></span><button class="btn r s" id="c_lv">Leave</button>${ed() ? '<button class="btn r s" id="c_end">End meeting for all</button>' : ""}</div>
      <div class="live"><i>Listening: </i><span id="iv"></span></div>
      <details class="opt"><summary>Chat</summary><div class="tr" id="chat" style="max-height:140px"></div><div class="row" style="margin-top:6px"><input id="c_msg" class="grow" placeholder="Write a message and press Enter"></div></details></div>`;
    layoutTiles();
    $("#c_mic").onclick = () => { S.local.getAudioTracks().forEach((t) => (t.enabled = !t.enabled)); drawRoomUI(); };
    $("#c_cam").onclick = () => { S.local.getVideoTracks().forEach((t) => (t.enabled = !t.enabled)); drawRoomUI(); };
    $("#c_sh").onclick = shareToggle;
    const r1 = $("#c_r1"), r2 = $("#c_r2"), rs = $("#c_rs"); if (r1) r1.onclick = () => startRec(true); if (r2) r2.onclick = () => startRec(false); if (rs) rs.onclick = () => { stopRec(); drawRoomUI(); };
    $("#c_ty").onclick = () => { if (S.sr) stopTyping(); else startTyping(V("c_l")); drawRoomUI(); };
    $("#c_l").onchange = () => { if (S.sr) S.sr.setLang(V("c_l")); };
    $("#c_lv").onclick = () => leave(false); const ce = $("#c_end"); if (ce) ce.onclick = () => { if (confirm("End the meeting for everyone?")) leave(true); };
    $("#c_msg").onkeydown = (e) => { if (e.key === "Enter" && e.target.value.trim()) { const x = e.target.value.trim(); S.room.data({ t: "chat", n: myName(), x }); chatAdd("You", x); e.target.value = ""; } };
  }
  async function shareToggle() {
    try {
      if (S.share) { S.share.getTracks().forEach((t) => t.stop()); S.share = null; S.room.setTrack("video", S.camTrack); const me = S.tiles.get("me"); if (me) { me.video.srcObject = S.local; } drawRoomUI(); return; }
      S.share = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false }); const t = S.share.getVideoTracks()[0];
      S.room.setTrack("video", t); const me = S.tiles.get("me"); if (me) me.video.srcObject = S.share; t.onended = () => { if (S.share) shareToggle(); }; drawRoomUI();
    } catch (e) { if (e.name !== "NotAllowedError") say("Could not share the screen: " + e.message); }
  }
  async function leave(end) {
    stopTyping(); if (S.recOn) { stopRec(); await new Promise((r) => setTimeout(r, 1800)); }
    await flushLines(); clearInterval(S.saver); S.saver = null;
    if (S.room) S.room.leave(); S.room = null; if (S.local) S.local.getTracks().forEach((t) => t.stop()); if (S.share) S.share.getTracks().forEach((t) => t.stop());
    S.local = null; S.share = null; S.tiles.clear();
    try { if (end) await call("kmr_cn_meeting_state", { p_id: mt().id, p_state: "ended" }); } catch (e) { say(e.message); }
    await openMeeting(mt().id);
  }

  /* ---- Teams / Google Meet: minutes typed here, optional recording ---- */
  async function startExt() {
    const m = mt(); let mic = null;
    try { mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false } }); } catch (e) { say("The microphone is blocked. Allow it in the browser address bar."); return; }
    S.local = mic; S.extAudio = [];
    if (confirm("Also capture the sound of the Teams / Google Meet tab, so other people’s voices are recorded and typed?\n\nPress OK, choose the meeting tab and tick “Share tab audio”. Press Cancel to use the microphone only.")) {
      try { const d = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: true }); S.extAudio = d.getAudioTracks(); d.getVideoTracks().forEach((t) => t.stop()); if (!S.extAudio.length) say("No tab sound was shared. Only your microphone is used."); } catch (e) { /* cancelled */ }
    }
    try { if (m.status === "planned" && ed()) S.det.meeting = await call("kmr_cn_meeting_state", { p_id: m.id, p_state: "live" }); } catch (e) { say(e.message); }
    S.ext = true; drawMeeting();
  }
  function drawExtUI() {
    const m = mt();
    $("#live").innerHTML = `<div class="vp ${S.recOn ? "rec" : ""}"><div class="row"><b>Minutes are being typed here</b><span class="chip r ${S.recOn ? "" : "hide"}"><span class="dot"></span>Recording</span>${m.ext_url ? `<a class="btn o s" href="${esc(m.ext_url)}" target="_blank" rel="noopener">Open ${PROV[m.provider]}</a>` : ""}</div>
      <div class="ctl"><select id="c_l" style="width:auto">${langOpts(S.sr ? S.sr.lang : m.language)}</select><button class="btn o s ${S.sr ? "on" : ""}" id="c_ty">${S.sr ? "Stop typing" : "Type the spoken words"}</button>
        ${ed() && !lockedF("connect.recording-and-minutes") ? (S.recOn ? '<button class="btn r s" id="c_rs">Stop recording</button>' : '<button class="btn s" id="c_r2">Record the voices</button>') : ""}
        <span style="flex:1"></span><button class="btn r s" id="c_lv">Stop</button>${ed() ? '<button class="btn r s" id="c_end">End meeting</button>' : ""}</div>
      <div class="live"><i>Listening: </i><span id="iv"></span></div></div>`;
    $("#c_ty").onclick = () => { if (S.sr) stopTyping(); else startTyping(V("c_l")); drawExtUI(); };
    $("#c_l").onchange = () => { if (S.sr) S.sr.setLang(V("c_l")); };
    const r2 = $("#c_r2"), rs = $("#c_rs"); if (r2) r2.onclick = () => { startRec(false); drawExtUI(); }; if (rs) rs.onclick = () => { stopRec(); drawExtUI(); };
    $("#c_lv").onclick = () => leaveExt(false); const ce = $("#c_end"); if (ce) ce.onclick = () => { if (confirm("End the meeting?")) leaveExt(true); };
  }
  async function leaveExt(end) {
    stopTyping(); if (S.recOn) { stopRec(); await new Promise((r) => setTimeout(r, 1800)); }
    await flushLines(); clearInterval(S.saver); S.saver = null; if (S.local) S.local.getTracks().forEach((t) => t.stop()); (S.extAudio || []).forEach((t) => t.stop()); S.local = null; S.extAudio = null; S.ext = null;
    try { if (end) await call("kmr_cn_meeting_state", { p_id: mt().id, p_state: "ended" }); } catch (e) { say(e.message); }
    await openMeeting(mt().id);
  }

  /* ================= remote devices ================= */
  function drawDev() {
    const D = S.load.devices, SS = S.load.sessions, devSt = (d) => d.status === "disabled" ? '<span class="chip x">Switched off</span>' : d.status === "waiting" ? '<span class="chip a">Waiting to be paired</span>' : d.online ? '<span class="ok2"></span><b>Online</b>' : '<span class="ok2 off"></span>Offline · ' + esc(ago(d.last_seen));
    $("#dev").innerHTML = `<div class="row"><h3 class="grow" style="margin:0">Remote devices</h3>${adm() ? '<button class="btn" id="da">+ Add a laptop or PC</button>' : ""}</div>
      <div class="guide">Install the small KMR Connect helper once on each laptop or PC. After that you can see and control it from here, from any browser or phone: screen, mouse, keyboard, files, folders, drives and programs. Every session is written in the list below.</div>
      ${D.length ? `<table><thead><tr><th>S.No</th><th>Device</th><th>System</th><th>Plant</th><th>Status</th><th>Computer</th><th></th></tr></thead><tbody>${D.map((d, i) => `<tr><td>${i + 1}</td><td><b>${esc(d.name)}</b></td><td>${esc(d.os_name || "")}</td><td>${esc(d.plant || "")}</td><td>${devSt(d)}</td><td>${esc((d.info && d.info.host) || "")} ${esc((d.info && d.info.user) || "")}</td><td>${ed() && d.status === "paired" ? `<button class="btn s" data-c="${d.id}" ${d.online ? "" : 'title="This device looks offline"'}>Connect</button> ` : ""}${adm() ? `<button class="btn o s" data-r="${d.id}">Pair again</button> <button class="btn o s" data-o="${d.id}">${d.status === "disabled" ? "Switch on" : "Switch off"}</button> <button class="btn r s" data-x="${d.id}">Remove</button>` : ""}</td></tr>`).join("")}</tbody></table>` : '<div class="empty">No device yet.<br>Press “+ Add a laptop or PC”.</div>'}
      <h3 style="margin-top:18px">Remote session list</h3>${SS.length ? sessTable(SS) : '<div class="empty">No session yet.</div>'}`;
    const a = $("#da"); if (a) a.onclick = addDevice;
    const dev = (id) => D.find((x) => x.id === id);
    $("#dev").querySelectorAll("[data-c]").forEach((b) => (b.onclick = () => connectDevice(dev(b.dataset.c))));
    $("#dev").querySelectorAll("[data-r]").forEach((b) => (b.onclick = async () => { if (!confirm("Pair this device again? The helper on the laptop must be set up again with the new code.")) return; try { showPair(dev(b.dataset.r).name, await call("kmr_cn_device_repair", { p_id: b.dataset.r })); } catch (e) { alert(e.message); } }));
    $("#dev").querySelectorAll("[data-o]").forEach((b) => (b.onclick = async () => { const d = dev(b.dataset.o); try { await call("kmr_cn_device_status", { p_id: d.id, p_status: d.status === "disabled" ? "paired" : "disabled" }); await loadAll(); drawDev(); } catch (e) { alert(e.message); } }));
    $("#dev").querySelectorAll("[data-x]").forEach((b) => (b.onclick = async () => { if (!confirm("Remove this device? The helper on it will stop working.")) return; try { await call("kmr_cn_device_delete", { p_id: b.dataset.x }); await loadAll(); drawDev(); } catch (e) { alert(e.message); } }));
    clearInterval(S.poll); S.poll = setInterval(async () => { if (hashGo() !== "dev" || S.v) return; try { await loadAll(); drawDev(); } catch (e) { /* keep the old view */ } }, 30000);
  }
  function addDevice() {
    open(`<h3>Add a laptop or PC</h3><div class="frm"><div><label class="lbl">Name of the device</label><input id="d_n" placeholder="e.g. Accounts laptop"></div><div><label class="lbl">System</label><select id="d_o"><option>Windows</option></select></div><div><label class="lbl">Plant / place (optional)</label><input id="d_p"></div></div>
      <div class="row" style="margin-top:12px"><button class="btn" id="d_s">Create the pairing code</button><button class="btn o" id="d_c">Cancel</button></div>`);
    $("#d_c").onclick = closeM;
    $("#d_s").onclick = async () => { try { const n = V("d_n"), r = await call("kmr_cn_device_add", { p_name: n, p_os: V("d_o"), p_plant: V("d_p") }); await loadAll(); drawDev(); showPair(n, r); } catch (e) { alert(e.message); } };
  }
  function showPair(name, r) {
    open(`<h3>Set up “${esc(name)}”</h3><div class="guide">On that laptop: <b>1.</b> Download and unzip the helper. <b>2.</b> Double-click <b>INSTALL_CONNECT.bat</b>. <b>3.</b> Type the two lines below when it asks. It then starts by itself with Windows and sits hidden next to the clock.</div>
      <p><a class="btn" href="/it/connect-helper.zip" download>Download the KMR Connect helper</a></p>
      <div class="kv"><div><span>Device ID</span><b style="font-family:monospace;user-select:all">${esc(r.id)}</b></div></div><p><span class="mut">Pairing code (valid 2 hours, shown only now):</span><br><span class="code" style="user-select:all">${esc(r.pair_code)}</span></p>
      <div class="note">The pairing code works once. If it expires, use “Pair again”.</div><div class="row"><button class="btn" id="d_k">Done</button></div>`);
    $("#d_k").onclick = closeM;
  }

  /* ---- the remote screen ---- */
  async function connectDevice(d) {
    let r; try { r = await call("kmr_cn_connect", { p_device: d.id }); } catch (e) { alert(e.message); return; }
    S.sess = r.session; const note = { v: "" };
    const ov = document.createElement("div"); ov.className = "rv"; ov.innerHTML = `<div class="bar2"><b>${esc(d.name)}</b><span class="st" id="rs">Calling…</span><span style="flex:1"></span>
      <button class="btn o s" id="r_fit">Real size</button><button class="btn o s" id="r_fs">Full screen</button>
      <details class="mm"><summary class="btn o s">Keys ▾</summary><div><button class="btn o s" data-k="Win">Windows key</button><button class="btn o s" data-k="AltTab">Alt + Tab</button><button class="btn o s" data-k="Esc">Esc</button><button class="btn o s" data-k="TaskMgr">Task Manager</button><button class="btn o s" data-k="Lock">Lock (Win + L)</button><button class="btn o s" data-k="Run">Run (Win + R)</button><button class="btn o s" data-k="Desk">Show desktop</button></div></details>
      <button class="btn o s" id="r_ty">Type text</button><button class="btn o s" id="r_cl">Clipboard</button><button class="btn o s" id="r_fl">Files</button><button class="btn o s" id="r_cm">Commands</button><button class="btn r s" id="r_end">End session</button></div>
      <div class="stage"><video id="rvid" tabindex="0" autoplay playsinline muted></video><div class="dr hide" id="rdr"></div></div>`;
    document.body.append(ov); const vid = ov.querySelector("#rvid"), st = ov.querySelector("#rs"), dr = ov.querySelector("#rdr");
    const setSt = (t, k) => { st.textContent = t; st.className = "st " + (k || ""); };
    const v = S.v = R.Viewer({ sb: QP.sb, secret: r.secret, who: email(), video: vid, onStatus: setSt, onConnected: () => { vid.focus(); } });
    /* mouse, touch and keyboard -> the device */
    const pos = (cx, cy) => { const b = vid.getBoundingClientRect(), vw = vid.videoWidth || 16, vh = vid.videoHeight || 9; let w = b.width, h = b.height, ox = 0, oy = 0; if (!vid.classList.contains("act")) { const k = Math.min(b.width / vw, b.height / vh); w = vw * k; h = vh * k; ox = (b.width - w) / 2; oy = (b.height - h) / 2; } else { w = vw; h = vh; ox = (b.width - w) / 2; oy = (b.height - h) / 2; } return { x: Math.min(1, Math.max(0, (cx - b.left - ox) / w)), y: Math.min(1, Math.max(0, (cy - b.top - oy) / h)) }; };
    let lastMove = 0; const mv = (e) => { const n = Date.now(); if (n - lastMove < 25) return; lastMove = n; v.send(Object.assign({ t: "m", a: "move" }, pos(e.clientX, e.clientY))); };
    vid.addEventListener("mousemove", mv); vid.addEventListener("mousedown", (e) => { vid.focus(); v.send(Object.assign({ t: "m", a: "down", b: e.button }, pos(e.clientX, e.clientY))); e.preventDefault(); });
    vid.addEventListener("mouseup", (e) => { v.send(Object.assign({ t: "m", a: "up", b: e.button }, pos(e.clientX, e.clientY))); e.preventDefault(); });
    vid.addEventListener("wheel", (e) => { v.send({ t: "m", a: "wheel", dy: e.deltaY }); e.preventDefault(); }, { passive: false }); vid.addEventListener("contextmenu", (e) => e.preventDefault());
    vid.addEventListener("keydown", (e) => { v.send({ t: "k", a: "down", code: e.code, key: e.key, c: e.ctrlKey, al: e.altKey, mt: e.metaKey }); e.preventDefault(); }); vid.addEventListener("keyup", (e) => { v.send({ t: "k", a: "up", code: e.code, key: e.key }); e.preventDefault(); });
    let tp = null, lp = null;   // touch: one finger moves the pointer and a short tap clicks, a long press right-clicks, two fingers scroll
    vid.addEventListener("touchstart", (e) => { const t = e.touches[0]; tp = { x: t.clientX, y: t.clientY, at: Date.now(), moved: false, two: e.touches.length > 1, y2: t.clientY }; if (!tp.two) { v.send(Object.assign({ t: "m", a: "move" }, pos(t.clientX, t.clientY))); lp = setTimeout(() => { if (tp && !tp.moved) { v.send(Object.assign({ t: "m", a: "down", b: 2 }, pos(tp.x, tp.y))); v.send(Object.assign({ t: "m", a: "up", b: 2 }, pos(tp.x, tp.y))); tp.done = true; } }, 600); } e.preventDefault(); }, { passive: false });
    vid.addEventListener("touchmove", (e) => { if (!tp) return; const t = e.touches[0]; if (Math.abs(t.clientX - tp.x) + Math.abs(t.clientY - tp.y) > 8) tp.moved = true; if (e.touches.length > 1 || tp.two) { v.send({ t: "m", a: "wheel", dy: (tp.y2 - t.clientY) * 3 }); tp.y2 = t.clientY; } else mv(t); e.preventDefault(); }, { passive: false });
    vid.addEventListener("touchend", (e) => { clearTimeout(lp); if (tp && !tp.moved && !tp.two && !tp.done && Date.now() - tp.at < 500) { const p = pos(tp.x, tp.y); v.send(Object.assign({ t: "m", a: "down", b: 0 }, p)); v.send(Object.assign({ t: "m", a: "up", b: 0 }, p)); } tp = null; e.preventDefault(); }, { passive: false });
    const KEYS = { Win: [["Meta"]], AltTab: [["Alt", "Tab"]], Esc: [["Escape"]], TaskMgr: [["Control", "Shift", "Escape"]], Lock: [["Meta", "KeyL"]], Run: [["Meta", "KeyR"]], Desk: [["Meta", "KeyD"]] };
    const CODE = { Meta: "MetaLeft", Alt: "AltLeft", Control: "ControlLeft", Shift: "ShiftLeft", Tab: "Tab", Escape: "Escape" };
    ov.querySelectorAll("[data-k]").forEach((b) => (b.onclick = () => { const seq = KEYS[b.dataset.k][0].map((k) => CODE[k] || k); seq.forEach((c) => v.send({ t: "k", a: "down", code: c, key: "" })); seq.slice().reverse().forEach((c) => v.send({ t: "k", a: "up", code: c, key: "" })); document.querySelectorAll("details.mm").forEach((x) => x.removeAttribute("open")); vid.focus(); }));
    ov.querySelector("#r_fit").onclick = (e) => { vid.classList.toggle("act"); e.target.textContent = vid.classList.contains("act") ? "Fit to screen" : "Real size"; };
    ov.querySelector("#r_fs").onclick = () => { if (document.fullscreenElement) document.exitFullscreen(); else ov.requestFullscreen && ov.requestFullscreen(); };
    ov.querySelector("#r_ty").onclick = () => { const t = prompt("Type the text to send to the device:"); if (t) v.send({ t: "text", s: t }); vid.focus(); };
    ov.querySelector("#r_cl").onclick = async () => {
      const c = confirm("OK = send the text in YOUR clipboard to the device.\nCancel = bring the DEVICE clipboard here.");
      try { if (c) { const t = await navigator.clipboard.readText(); await v.call({ op: "clip_set", text: t }); say("Sent to the device clipboard.", true); } else { const m = await v.call({ op: "clip_get" }); try { await navigator.clipboard.writeText(m.text || ""); say("Device clipboard copied here.", true); } catch (e) { prompt("Device clipboard:", m.text || ""); } } } catch (e) { alert(e.message); }
    };
    const panel = (html) => { dr.classList.remove("hide"); dr.innerHTML = `<div class="row"><b class="grow">${html.title}</b><button class="btn o s" id="dr_x">Close</button></div>${html.body}`; dr.querySelector("#dr_x").onclick = () => dr.classList.add("hide"); };
    ov.querySelector("#r_fl").onclick = () => filePanel(v, panel, dr);
    ov.querySelector("#r_cm").onclick = () => cmdPanel(v, panel, dr);
    ov.querySelector("#r_end").onclick = async () => { const n = prompt("Note for the session list (optional):", "") || ""; try { v.close(); } catch (e) { /* ignore */ } ov.remove(); S.v = null; try { await call("kmr_cn_session_end", { p_session: r.session, p_note: n }); } catch (e) { /* ignore */ } if (document.fullscreenElement) document.exitFullscreen().catch(() => { }); await loadAll(); drawDev(); };
  }
  const fsz = (n) => (n == null ? "" : n > 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.ceil(n / 1024) + " KB");
  async function filePanel(v, panel, dr) {
    let cwd = "";
    panel({ title: "Files and folders", body: '<div id="fp"></div>' });
    const draw = async (p) => {
      const box = dr.querySelector("#fp"); box.innerHTML = '<span class="mut">Reading…</span>';
      try {
        const r = await v.call({ op: "ls", path: p }); cwd = r.path || "";
        const up = cwd ? cwd.replace(/[\\/][^\\/]*[\\/]?$/, "") : ""; const parent = cwd && /^[A-Za-z]:\\?$/.test(cwd) ? "" : (up && !/[\\/]/.test(up) ? up + "\\" : up);
        box.innerHTML = `<div class="row"><input id="fp_p" class="grow" value="${esc(cwd)}" placeholder="Drives"><button class="btn s" id="fp_g">Go</button>${cwd ? '<button class="btn o s" id="fp_u">Up</button>' : ""}</div>
          ${cwd ? '<div class="row"><button class="btn o s" id="fp_up">Send a file here</button><button class="btn o s" id="fp_nf">New folder</button><input type="file" id="fp_f" class="hide" multiple></div>' : ""}
          <table><thead><tr><th>Name</th><th>Size</th><th></th></tr></thead><tbody>${(r.items || []).map((x, i) => `<tr><td>${x.dir ? `<a href="#" data-d="${i}">📁 ${esc(x.name)}</a>` : "📄 " + esc(x.name)}</td><td>${x.dir ? "" : fsz(x.size)}</td><td>${x.dir && cwd ? "" : x.dir ? "" : `<button class="btn o s" data-g="${i}">Get</button> `}${cwd ? `<button class="btn o s" data-n="${i}">Rename</button> <button class="btn r s" data-x="${i}">Delete</button>` : ""}${!x.dir && cwd ? ` <button class="btn o s" data-o="${i}">Open</button>` : ""}</td></tr>`).join("")}</tbody></table>`;
        const full = (x) => (cwd.endsWith("\\") ? cwd : cwd + "\\") + x.name, item = (i) => r.items[+i], path = (x) => (cwd ? full(x) : x.name);
        box.querySelector("#fp_g").onclick = () => draw(V("fp_p")); const u = box.querySelector("#fp_u"); if (u) u.onclick = () => draw(parent);
        box.querySelectorAll("[data-d]").forEach((a) => (a.onclick = (e) => { e.preventDefault(); draw(path(item(a.dataset.d))); }));
        box.querySelectorAll("[data-g]").forEach((b) => (b.onclick = () => download(v, full(item(b.dataset.g)), item(b.dataset.g).name, b)));
        box.querySelectorAll("[data-o]").forEach((b) => (b.onclick = async () => { try { await v.call({ op: "start", path: full(item(b.dataset.o)) }); say("Opened on the device.", true); } catch (e) { alert(e.message); } }));
        box.querySelectorAll("[data-n]").forEach((b) => (b.onclick = async () => { const x = item(b.dataset.n), n = prompt("New name:", x.name); if (!n || n === x.name) return; try { await v.call({ op: "ren", path: full(x), to: n }); draw(cwd); } catch (e) { alert(e.message); } }));
        box.querySelectorAll("[data-x]").forEach((b) => (b.onclick = async () => { const x = item(b.dataset.x); if (!confirm("Delete “" + x.name + "” on the device? It goes to the Recycle Bin.")) return; try { await v.call({ op: "del", path: full(x) }); draw(cwd); } catch (e) { alert(e.message); } }));
        const nf = box.querySelector("#fp_nf"); if (nf) nf.onclick = async () => { const n = prompt("Folder name:"); if (!n) return; try { await v.call({ op: "mkdir", path: (cwd.endsWith("\\") ? cwd : cwd + "\\") + n }); draw(cwd); } catch (e) { alert(e.message); } };
        const fb = box.querySelector("#fp_up"), fi = box.querySelector("#fp_f"); if (fb) { fb.onclick = () => fi.click(); fi.onchange = async () => { for (const f of fi.files) { try { await upload(v, (cwd.endsWith("\\") ? cwd : cwd + "\\") + f.name, f, fb); } catch (e) { alert(f.name + ": " + e.message); } } draw(cwd); }; }
      } catch (e) { box.innerHTML = `<div class="msg">${esc(e.message)}</div>`; }
    };
    draw("");
  }
  const b64 = (buf) => { let s = ""; const a = new Uint8Array(buf); for (let i = 0; i < a.length; i += 0x8000) s += String.fromCharCode.apply(null, a.subarray(i, i + 0x8000)); return btoa(s); };
  async function download(v, path, name, btn) {
    const old = btn.textContent, parts = []; let off = 0;
    try { for (;;) { const r = await v.call({ op: "read", path, off, len: 98304 }, 60000); const bin = atob(r.b64 || ""), a = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i); parts.push(a); off += a.length; btn.textContent = r.size ? Math.round((off / r.size) * 100) + "%" : off + " B"; if (r.eof || !a.length) break; }
      const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob(parts)); a.download = name; a.click(); } catch (e) { alert(e.message); }
    btn.textContent = old;
  }
  async function upload(v, path, file, btn) {
    const old = btn.textContent; let off = 0;
    try { do { const buf = await file.slice(off, off + 98304).arrayBuffer(); await v.call({ op: "write", path, off, b64: b64(buf), first: off === 0 }, 60000); off += buf.byteLength; btn.textContent = Math.round((off / Math.max(1, file.size)) * 100) + "%"; } while (off < file.size); } finally { btn.textContent = old; }
  }
  function cmdPanel(v, panel, dr) {
    panel({ title: "Run a command or open a program", body: `<div class="note">Runs on the device as the signed-in Windows user. Everything is written to the helper’s log.</div><div class="row"><select id="cm_s" style="width:auto"><option value="powershell">PowerShell</option><option value="cmd">Command prompt</option></select><input id="cm_c" class="grow" placeholder="e.g. Get-Process | Sort CPU -desc | select -first 10"><button class="btn s" id="cm_r">Run</button></div><div class="row"><input id="cm_p" class="grow" placeholder="Open a program or file, e.g. notepad.exe or D:\\Reports\\a.xlsx"><button class="btn o s" id="cm_o">Open</button></div><div class="row"><button class="btn o s" id="cm_t">Show running programs</button></div><pre class="out" id="cm_out">Nothing run yet.</pre>` });
    const out = dr.querySelector("#cm_out"), show = (m) => { out.textContent = (m.out || "") + (m.err ? "\n[errors]\n" + m.err : "") + "\n[exit code " + m.code + "]"; };
    dr.querySelector("#cm_r").onclick = async () => { out.textContent = "Running…"; try { show(await v.call({ op: "run", shell: V("cm_s"), cmd: V("cm_c"), timeout: 60 }, 90000)); } catch (e) { out.textContent = e.message; } };
    dr.querySelector("#cm_c").onkeydown = (e) => { if (e.key === "Enter") dr.querySelector("#cm_r").click(); };
    dr.querySelector("#cm_o").onclick = async () => { try { await v.call({ op: "start", path: V("cm_p") }); out.textContent = "Opened."; } catch (e) { out.textContent = e.message; } };
    dr.querySelector("#cm_t").onclick = async () => { try { const r = await v.call({ op: "ps" }); out.textContent = (r.items || []).map((p) => (p.id + "").padEnd(7) + p.name.padEnd(28) + Math.round(p.mb) + " MB" + (p.title ? "   " + p.title : "")).join("\n"); } catch (e) { out.textContent = e.message; } };
  }

  (async () => {
    try {
      await QP.init("connect", "kmr_cn_context"); if (!QP.ctx) return;
      $("#role").textContent = email() + " · " + QP.ctx.role; route();
    } catch (e) { say(e.message); }
  })();
})();
