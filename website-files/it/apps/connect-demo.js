/* KMR Connect - sample mode (?demo=1): nothing is stored; two browser tabs on the same computer can join the same room to try the video room. */
(function () {
  "use strict";
  const id = () => "x" + Math.random().toString(36).slice(2, 9), iso = (ms) => new Date(ms).toISOString(), now = () => Date.now();
  let n = 0; const meets = [], segs = [], devices = [], sessions = [];
  const mk = (o) => { const m = Object.assign({ id: id(), meeting_no: "CN-2611-000" + (++n), provider: "kmr", language: "en-IN", attendees: [], status: "planned", scheduled_at: iso(now() + 36e5), room: "demo-room-key", started_at: null, ended_at: null, mom_id: null }, o); meets.push(m); return m; };
  mk({ id: "demo-meeting-1", title: "Customer quality review (sample)" });
  devices.push({ id: "dev-demo", name: "Accounts laptop (sample)", os_name: "Windows", plant: "Plant-1", status: "paired", online: false, last_seen: iso(now() - 864e5), info: {} });
  const view = (m) => Object.assign({}, m, { room: undefined, lines: segs.filter((s) => s.meeting_id === m.id).length, recordings: 0 });
  const find = (i) => meets.find((m) => m.id === i) || (() => { throw new Error("Meeting not found."); })();
  window.QP_DEMO = {
    kmr_cn_context() { return { role: "admin", cid: "demo", company: "Demo Engineering (sample data)", email: "demo@example.com", has_mom: false }; },
    kmr_cn_load() { return { devices, meetings: meets.map(view), sessions, people: [{ email: "demo@example.com" }, { email: "ravi@example.com" }], today: iso(now()).slice(0, 10) }; },
    kmr_cn_meeting_save(a) { const p = a.p; if (p.id) { Object.assign(find(p.id), { title: p.title, provider: p.provider, ext_url: p.ext_url, language: p.language, attendees: p.attendees, agenda: p.agenda, scheduled_at: p.scheduled_at }); return view(find(p.id)); } if (!p.title) throw new Error("Enter the meeting title."); return view(mk({ title: p.title, provider: p.provider, ext_url: p.ext_url, language: p.language, attendees: p.attendees, agenda: p.agenda, scheduled_at: p.scheduled_at })); },
    kmr_cn_meeting_get(a) { const m = find(a.p_id); return { meeting: view(m), room: m.provider === "kmr" ? m.room : null, segments: segs.filter((s) => s.meeting_id === m.id), recordings: m.recs || [] }; },
    kmr_cn_meeting_state(a) { const m = find(a.p_id); if (a.p_state === "live") { m.status = "live"; m.started_at = m.started_at || iso(now()); } else { m.status = "ended"; m.ended_at = iso(now()); } return view(m); },
    kmr_cn_meeting_void(a) { meets.splice(meets.indexOf(find(a.p_id)), 1); },
    kmr_cn_seg_save(a) { a.p.segs.forEach((s) => { if (!segs.some((x) => x.client_id === s.client_id)) segs.push(Object.assign({ meeting_id: a.p.meeting_id }, s)); }); return { saved: a.p.segs.length }; },
    kmr_cn_device_add(a) { if (!a.p_name) throw new Error("Enter a name for the device, for example “Accounts laptop”."); const d = { id: id(), name: a.p_name, os_name: a.p_os, plant: a.p_plant, status: "waiting", online: false, last_seen: null, info: {} }; devices.push(d); return { id: d.id, pair_code: "DEMO-2345" }; },
    kmr_cn_device_repair(a) { return { id: a.p_id, pair_code: "DEMO-6789" }; },
    kmr_cn_device_status(a) { const d = devices.find((x) => x.id === a.p_id); d.status = a.p_status; },
    kmr_cn_device_delete(a) { devices.splice(devices.findIndex((x) => x.id === a.p_id), 1); },
    kmr_cn_connect(a) { const d = devices.find((x) => x.id === a.p_device); const s = { id: id(), device_name: d.name, started_by: "demo@example.com", started_at: iso(now()), ended_at: null }; sessions.unshift(s); return { secret: "demo-secret", session: s.id, name: d.name }; },
    kmr_cn_session_end(a) { const s = sessions.find((x) => x.id === a.p_session); if (s) { s.ended_at = iso(now()); s.note = a.p_note; } },
    kmr_cn_rec_add() { return { id: id() } }
  };
})();
