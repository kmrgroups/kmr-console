"use client";
import { useEffect, useRef } from "react";

/**
 * KMR "3D fusion" sign-in scene — the same concept as Balloon Inspector / Process Documents, shared by every
 * KMR product: a violet studio with aurora light, a neon floor, orbiting light trails, and a chrome product object
 * that thousands of coloured particles assemble into and dissolve out of, with floating call-outs.
 * `variant` picks the product object. Drawn live with three.js (loaded only on this screen).
 */
export type FusionVariant = "hrm" | "console";

export function FusionScene({ variant, chip, headline, em, sub, tags }: {
  variant: FusionVariant; chip: string; headline: string; em: string; sub: string; tags: string[];
}) {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let stop = () => {};
    let alive = true;
    (async () => {
      const el = host.current;
      if (!el || !webglOK()) return;
      const T = await import("three");
      if (!alive) return;
      try { stop = build(T, el, variant); el.classList.add("ready"); } catch (e) { console.warn("3D scene:", e); }
    })();
    return () => { alive = false; stop(); };
  }, [variant]);

  return (
    <section ref={host} className="fz-vis" aria-hidden="true">
      <div className="fz-aur"><i /><i /><i /><i /></div>
      <canvas />
      <div className="fz-chip"><span className="ring">{chip.slice(0, 1)}</span><span>{chip}</span></div>
      <div className="fz-cap">
        <div><h3>{headline} <em>{em}</em></h3><p>{sub}</p></div>
        <div className="fz-tags">{tags.map((t) => <span key={t}>{t}</span>)}</div>
      </div>
    </section>
  );
}

function webglOK() {
  try { const c = document.createElement("canvas"); return !!(window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl"))); } catch { return false; }
}

type Three = typeof import("three");

function build(T: Three, host: HTMLElement, variant: FusionVariant): () => void {
  const cv = host.querySelector("canvas") as HTMLCanvasElement;
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const R = new T.WebGLRenderer({ canvas: cv, antialias: true, alpha: true, powerPreference: "high-performance" });
  R.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  R.outputColorSpace = T.SRGBColorSpace; R.toneMapping = T.ACESFilmicToneMapping; R.toneMappingExposure = 1.3; R.setClearColor(0x000000, 0);
  const S = new T.Scene(), cam = new T.PerspectiveCamera(30, 1, 0.1, 100);
  S.fog = new T.FogExp2(0x0a0720, 0.05);
  const ADD = T.AdditiveBlending;
  const tex = (c: HTMLCanvasElement) => { const t = new T.CanvasTexture(c); t.colorSpace = T.SRGBColorSpace; t.anisotropy = R.capabilities.getMaxAnisotropy(); return t; };
  const radial = (stops: [number, string][], size = 256) => {
    const c = document.createElement("canvas"); c.width = c.height = size; const x = c.getContext("2d")!, h = size / 2;
    const g = x.createRadialGradient(h, h, 0, h, h, h); stops.forEach(([o, col]) => g.addColorStop(o, col)); x.fillStyle = g; x.fillRect(0, 0, size, size); return tex(c);
  };

  // colourful studio reflections for the chrome
  const ec = document.createElement("canvas"); ec.width = 2048; ec.height = 1024; const g = ec.getContext("2d")!;
  const gr = g.createLinearGradient(0, 0, 0, 1024); gr.addColorStop(0, "#2A1B5C"); gr.addColorStop(0.48, "#1A1040"); gr.addColorStop(0.55, "#0E0A26"); gr.addColorStop(1, "#05030F");
  g.fillStyle = gr; g.fillRect(0, 0, 2048, 1024);
  ([[180, 220, 380, 130, "#FFFFFF"], [700, 160, 300, 110, "#22D3EE"], [1150, 210, 420, 120, "#F0ABFC"], [1650, 260, 300, 140, "#FBBF24"], [420, 470, 520, 50, "#A855F7"], [1300, 520, 560, 60, "#06B6D4"]] as [number, number, number, number, string][])
    .forEach(([x, y, w, h, c]) => { g.save(); g.filter = "blur(22px)"; g.fillStyle = c; g.fillRect(x, y, w, h); g.restore(); });
  const et = new T.CanvasTexture(ec); et.mapping = T.EquirectangularReflectionMapping; et.colorSpace = T.SRGBColorSpace;
  const pm = new T.PMREMGenerator(R); S.environment = pm.fromEquirectangular(et).texture; et.dispose(); pm.dispose();

  S.add(new T.HemisphereLight(0xc4b5fd, 0x0b0720, 0.55));
  const key = new T.DirectionalLight(0xffffff, 0.9); key.position.set(4, 9, 6); S.add(key);
  const orbs = ([[0xff2bd6, 0], [0x22e5ff, 2.1], [0xffb020, 4.2]] as [number, number][]).map(([c, ph]) => {
    const l = new T.PointLight(c, 40, 14, 1.6); S.add(l);
    const halo = new T.Sprite(new T.SpriteMaterial({ map: radial([[0, "rgba(255,255,255,1)"], [0.15, "#" + c.toString(16).padStart(6, "0")], [1, "rgba(0,0,0,0)"]]), blending: ADD, transparent: true, depthWrite: false, opacity: 0.9 }));
    halo.scale.set(0.9, 0.9, 1); S.add(halo); return { l, halo, ph };
  });

  // neon floor
  const grid = new T.GridHelper(26, 52, 0xa855f7, 0x3b2a7a); (grid.material as import("three").Material).transparent = true; (grid.material as import("three").Material).opacity = 0.3; S.add(grid);
  const pool = new T.Mesh(new T.PlaneGeometry(9, 9), new T.MeshBasicMaterial({ map: radial([[0, "rgba(34,211,238,.55)"], [0.35, "rgba(124,58,237,.35)"], [0.7, "rgba(236,72,153,.12)"], [1, "rgba(0,0,0,0)"]], 512), transparent: true, blending: ADD, depthWrite: false }));
  pool.rotation.x = -Math.PI / 2; pool.position.y = 0.01; S.add(pool);
  const rpts: import("three").Vector3[] = [];
  for (let i = 0; i < 120; i++) { const a = (i / 120) * Math.PI * 2, r1 = 3.25, r2 = i % 10 ? 3.12 : 2.95; rpts.push(new T.Vector3(Math.cos(a) * r1, 0.02, Math.sin(a) * r1), new T.Vector3(Math.cos(a) * r2, 0.02, Math.sin(a) * r2)); }
  const tick = new T.LineSegments(new T.BufferGeometry().setFromPoints(rpts), new T.LineBasicMaterial({ color: 0x22d3ee, transparent: true, opacity: 0.7, blending: ADD })); S.add(tick);
  const pulses = [0, 1, 2].map((i) => { const m = new T.Mesh(new T.RingGeometry(1, 1.04, 128), new T.MeshBasicMaterial({ color: [0x22d3ee, 0xa855f7, 0xf472b6][i], transparent: true, opacity: 0, blending: ADD, side: T.DoubleSide, depthWrite: false })); m.rotation.x = -Math.PI / 2; m.position.y = 0.015; S.add(m); return m; });
  const trails = ([[3.4, 0.35, 0x22d3ee, 0.5], [3.8, -0.25, 0xf472b6, -0.38], [3.6, 0.9, 0xfbbf24, 0.3]] as [number, number, number, number][]).map(([r, tilt, c, sp]) => {
    const cc = document.createElement("canvas"); cc.width = 512; cc.height = 4; const x = cc.getContext("2d")!, lg = x.createLinearGradient(0, 0, 512, 0);
    lg.addColorStop(0, "rgba(255,255,255,0)"); lg.addColorStop(0.7, "rgba(255,255,255,.35)"); lg.addColorStop(1, "rgba(255,255,255,1)"); x.fillStyle = lg; x.fillRect(0, 0, 512, 4);
    const m = new T.Mesh(new T.TorusGeometry(r, 0.012, 6, 256, Math.PI * 1.2), new T.MeshBasicMaterial({ color: c, map: tex(cc), transparent: true, opacity: 0.75, blending: ADD, depthWrite: false }));
    const gp = new T.Group(); gp.add(m); gp.rotation.x = Math.PI / 2 + tilt; gp.position.y = 1; S.add(gp); return { gp, sp };
  });

  // the product object
  const metal = new T.MeshStandardMaterial({ color: 0xeef1fa, metalness: 0.9, roughness: 0.18, envMapIntensity: 2.1 });
  const part = new T.Group(); S.add(part);
  const holoM = new T.LineBasicMaterial({ color: 0x67e8f9, transparent: true, opacity: 0.3, blending: ADD, depthWrite: false });
  let surface: () => [number, number, number];
  let scanner: import("three").Object3D | null = null;
  const spin: import("three").Object3D[] = [];

  if (variant === "hrm") {
    // chrome employee ID badge with a photo ring, text bars and a clip — standing, slowly turning
    const w = 2.2, h = 3.0, rr = 0.28, sh = new T.Shape();
    sh.moveTo(-w / 2 + rr, -h / 2); sh.lineTo(w / 2 - rr, -h / 2); sh.quadraticCurveTo(w / 2, -h / 2, w / 2, -h / 2 + rr); sh.lineTo(w / 2, h / 2 - rr);
    sh.quadraticCurveTo(w / 2, h / 2, w / 2 - rr, h / 2); sh.lineTo(-w / 2 + rr, h / 2); sh.quadraticCurveTo(-w / 2, h / 2, -w / 2, h / 2 - rr); sh.lineTo(-w / 2, -h / 2 + rr); sh.quadraticCurveTo(-w / 2, -h / 2, -w / 2 + rr, -h / 2);
    const slot = new T.Path(); slot.absellipse(0, h / 2 - 0.25, 0.28, 0.07, 0, Math.PI * 2, true); sh.holes.push(slot);
    const bg = new T.ExtrudeGeometry(sh, { depth: 0.12, bevelEnabled: true, bevelThickness: 0.03, bevelSize: 0.03, bevelSegments: 4, curveSegments: 48 }); bg.translate(0, 0, -0.06);
    const badge = new T.Group(); badge.position.y = 1.75; part.add(badge);
    const card = new T.Mesh(bg, metal); badge.add(card);
    badge.add(new T.LineSegments(new T.EdgesGeometry(bg, 25), holoM));
    const photo = new T.Mesh(new T.TorusGeometry(0.46, 0.05, 16, 96), new T.MeshBasicMaterial({ color: 0x22d3ee, transparent: true, blending: ADD })); photo.position.set(0, 0.55, 0.1); badge.add(photo);
    const head = new T.Mesh(new T.SphereGeometry(0.17, 32, 16), metal); head.position.set(0, 0.64, 0.1); badge.add(head);
    const body = new T.Mesh(new T.SphereGeometry(0.28, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2), metal); body.position.set(0, 0.2, 0.1); badge.add(body);
    [[-0.35, 0.72], [-0.5, 0.55], [-0.72, 0.4]].forEach(([y, len], i) => { const b = new T.Mesh(new T.BoxGeometry(len * 1.6, 0.07, 0.03), new T.MeshBasicMaterial({ color: [0xf472b6, 0xa5b4fc, 0xfbbf24][i], transparent: true, opacity: 0.85, blending: ADD })); b.position.set(0, y, 0.1); badge.add(b); });
    const clip = new T.Mesh(new T.TorusGeometry(0.22, 0.045, 12, 64), metal); clip.position.set(0, h / 2 + 0.12, 0); badge.add(clip);
    // face-ID scan: a glowing bar sweeping up and down the badge
    const sc = new T.Mesh(new T.PlaneGeometry(w * 1.25, 0.05), new T.MeshBasicMaterial({ color: 0x22d3ee, transparent: true, opacity: 0.9, blending: ADD, side: T.DoubleSide, depthWrite: false }));
    sc.position.z = 0.16; badge.add(sc); scanner = sc;
    spin.push(badge);
    surface = () => {
      const r = Math.random();
      if (r < 0.8) return [(Math.random() - 0.5) * w, 1.75 + (Math.random() - 0.5) * h, (Math.random() < 0.5 ? 0.09 : -0.09)];
      const a = Math.random() * Math.PI * 2; return [Math.cos(a) * 0.46, 1.75 + 0.55 + Math.sin(a) * 0.46, 0.1];
    };
  } else {
    // chrome KMR globe with meridians, and the three product tiles orbiting it
    const globe = new T.Mesh(new T.SphereGeometry(1.25, 96, 64), metal); globe.position.y = 1.75; part.add(globe);
    const lines = new T.Group(); lines.position.y = 1.75; part.add(lines);
    for (let i = 0; i < 12; i++) { const m = new T.Mesh(new T.TorusGeometry(1.27, 0.006, 6, 128), holoM); m.rotation.y = (i / 12) * Math.PI; lines.add(m); }
    for (let k = -2; k <= 2; k++) { const y = k * 0.42, r = Math.sqrt(1.27 * 1.27 - y * y); const m = new T.Mesh(new T.TorusGeometry(r, 0.006, 6, 128), holoM); m.rotation.x = Math.PI / 2; m.position.y = y; lines.add(m); }
    const eq = new T.Mesh(new T.TorusGeometry(1.36, 0.02, 12, 160), new T.MeshBasicMaterial({ color: 0xfbbf24, transparent: true, blending: ADD })); eq.rotation.x = Math.PI / 2 + 0.25; eq.position.y = 1.75; part.add(eq);
    spin.push(globe, lines);
    const tiles = new T.Group(); tiles.position.y = 1.75; part.add(tiles);
    ["HRM", "BALLOON", "DOCS"].forEach((label, i) => {
      const c = document.createElement("canvas"); c.width = 512; c.height = 320; const x = c.getContext("2d")!;
      const lg = x.createLinearGradient(0, 0, 512, 320); lg.addColorStop(0, ["#0ea5e9", "#a855f7", "#f59e0b"][i]); lg.addColorStop(1, "#1e1b4b"); x.fillStyle = lg;
      x.beginPath(); x.roundRect(8, 8, 496, 304, 40); x.fill(); x.strokeStyle = "rgba(255,255,255,.7)"; x.lineWidth = 6; x.stroke();
      x.fillStyle = "#fff"; x.font = "800 92px Montserrat, Arial Black, Arial"; x.textAlign = "center"; x.fillText(label, 256, 190);
      const tile = new T.Mesh(new T.PlaneGeometry(1.1, 0.69), new T.MeshBasicMaterial({ map: tex(c), transparent: true, side: T.DoubleSide }));
      const a = (i / 3) * Math.PI * 2; tile.position.set(Math.cos(a) * 2.6, Math.sin(i * 2) * 0.35, Math.sin(a) * 2.6); tile.userData.a = a; tiles.add(tile);
    });
    spin.push(tiles);
    surface = () => { const u = Math.random() * 2, v = Math.random(); const th = Math.PI * u, ph = Math.acos(2 * v - 1); return [1.25 * Math.sin(ph) * Math.cos(th), 1.75 + 1.25 * Math.cos(ph), 1.25 * Math.sin(ph) * Math.sin(th)]; };
  }

  // digital fusion: particles assemble into the object and dissolve out of it
  const NP = still ? 1 : 3600, home = new Float32Array(NP * 3), from = new Float32Array(NP * 3), cur = new Float32Array(NP * 3), col = new Float32Array(NP * 3), seed = new Float32Array(NP);
  const palette = [0x22d3ee, 0x818cf8, 0xc084fc, 0xf472b6, 0xfbbf24].map((c) => new T.Color(c));
  for (let i = 0; i < NP; i++) {
    const [x, y, z] = surface(); home.set([x, y, z], i * 3);
    const a = Math.random() * Math.PI * 2, e = (Math.random() - 0.3) * Math.PI * 0.6, d = 5 + Math.random() * 6;
    from.set([Math.cos(a) * Math.cos(e) * d, 1 + Math.sin(e) * d * 0.8 + Math.random() * 2, Math.sin(a) * Math.cos(e) * d], i * 3);
    const c = palette[Math.floor((y / 3.5) * 0.6 * palette.length + Math.random() * 2) % palette.length]; col.set([c.r, c.g, c.b], i * 3); seed[i] = Math.random();
  }
  const fgeo = new T.BufferGeometry(); fgeo.setAttribute("position", new T.BufferAttribute(cur, 3)); fgeo.setAttribute("color", new T.BufferAttribute(col, 3));
  const dot = radial([[0, "rgba(255,255,255,1)"], [0.25, "rgba(255,255,255,.8)"], [1, "rgba(255,255,255,0)"]], 64);
  const fusM = new T.PointsMaterial({ size: 0.11, map: dot, vertexColors: true, transparent: true, opacity: 0, blending: ADD, depthWrite: false, fog: false, toneMapped: false });
  const fusion = new T.Points(fgeo, fusM); part.add(fusion);

  // rising data streams
  const ND = 600, dp = new Float32Array(ND * 3), dc = new Float32Array(ND * 3);
  for (let i = 0; i < ND; i++) { const k = Math.floor(Math.random() * 40), a = (k / 40) * Math.PI * 2, r = 4.4 + (k % 3) * 0.5; dp.set([Math.cos(a) * r, Math.random() * 6, Math.sin(a) * r], i * 3); const c = palette[k % palette.length]; dc.set([c.r, c.g, c.b], i * 3); }
  const dgeo = new T.BufferGeometry(); dgeo.setAttribute("position", new T.BufferAttribute(dp, 3)); dgeo.setAttribute("color", new T.BufferAttribute(dc, 3));
  S.add(new T.Points(dgeo, new T.PointsMaterial({ size: 0.06, map: dot, vertexColors: true, transparent: true, opacity: 0.75, blending: ADD, depthWrite: false })));

  // floating call-outs
  const CALL = variant === "hrm"
    ? [["IN 09:02", "#22D3EE"], ["Face ID ✓", "#A855F7"], ["Leave approved", "#F472B6"], ["KMR-0042", "#FBBF24"]]
    : [["Licence active", "#22D3EE"], ["T-00012 resolved", "#A855F7"], ["Pilot request", "#F472B6"], ["3 products", "#FBBF24"]];
  const callouts = CALL.map(([txt, c], i) => {
    const cc = document.createElement("canvas"); cc.width = 512; cc.height = 128; const x = cc.getContext("2d")!;
    x.fillStyle = "rgba(15,10,40,.72)"; x.beginPath(); x.roundRect(6, 14, 500, 100, 50); x.fill(); x.strokeStyle = c; x.lineWidth = 5; x.stroke();
    x.fillStyle = c; x.beginPath(); x.arc(64, 64, 16, 0, 6.28); x.fill();
    x.fillStyle = "#fff"; x.font = "700 44px Segoe UI, Arial"; x.textBaseline = "middle"; x.fillText(txt, 100, 66);
    const s = new T.Sprite(new T.SpriteMaterial({ map: tex(cc), transparent: true, depthWrite: false, opacity: 0 }));
    const a = (i / CALL.length) * Math.PI * 2 + 0.6; s.position.set(Math.cos(a) * 2.25, 0.9 + (i % 2) * 1.9, Math.sin(a) * 2.25); s.scale.set(1.05, 0.26, 1); S.add(s); return s;
  });

  // animate
  let W = 1, H = 1, mx = 0, my = 0, raf = 0;
  const t0 = performance.now();
  const resize = () => { W = host.clientWidth || 1; H = host.clientHeight || 1; R.setSize(W, H, false); cam.aspect = W / H; cam.fov = W / H < 0.9 ? 40 : 30; cam.updateProjectionMatrix(); };
  const onMove = (e: PointerEvent) => { const b = host.getBoundingClientRect(); mx = (e.clientX - b.left) / b.width - 0.5; my = (e.clientY - b.top) / b.height - 0.5; };
  const CYCLE = 16;
  const frame = (now: number) => {
    const t = still ? 6 : (now - t0) / 1000;
    const ca = t * 0.12 + mx * 0.5;
    cam.position.set(Math.sin(ca) * 9.5, 3.2 - my * 1.2, Math.cos(ca) * 9.5); cam.lookAt(0, 1.6, 0);
    spin.forEach((o, i) => { o.rotation.y = t * (i === 2 ? -0.35 : 0.3); });
    // product tiles always face the viewer (no mirrored labels)
    if (variant === "console" && spin[2]) spin[2].children.forEach((c) => c.quaternion.copy(cam.quaternion));
    if (variant === "hrm" && spin[0]) spin[0].rotation.y = Math.sin(t * 0.5) * 0.7;
    if (scanner) scanner.position.y = Math.sin(t * 1.6) * 1.35;
    orbs.forEach(({ l, halo, ph }) => { const a = t * 0.45 + ph; l.position.set(Math.cos(a) * 3.8, 2.4 + Math.sin(a * 1.3), Math.sin(a) * 3.8); halo.position.copy(l.position); });
    trails.forEach(({ gp, sp }) => { gp.rotation.z = t * sp; });
    tick.rotation.y = t * 0.08;
    pulses.forEach((m, i) => { const f = ((t * 0.35 + i / 3) % 1); m.scale.setScalar(1 + f * 4); (m.material as import("three").MeshBasicMaterial).opacity = (1 - f) * 0.5; });
    // fusion cycle: gather 0–3 s, hold, scatter at 12–15 s
    const c = t % CYCLE, gather = c < 3 ? c / 3 : c < 12 ? 1 : c < 15 ? 1 - (c - 12) / 3 : 0;
    for (let i = 0; i < NP; i++) {
      const k = Math.min(1, Math.max(0, gather * 1.4 - seed[i] * 0.4)), e = 1 - Math.pow(1 - k, 3);
      for (let j = 0; j < 3; j++) cur[i * 3 + j] = from[i * 3 + j] + (home[i * 3 + j] - from[i * 3 + j]) * e;
    }
    fgeo.attributes.position.needsUpdate = true;
    fusM.opacity = 0.25 + 0.65 * (1 - Math.abs(gather - 0.5) * 2) + (gather > 0.95 ? 0.1 : 0);
    metal.opacity = 1; metal.transparent = false;
    part.scale.setScalar(0.96 + gather * 0.04);
    for (let i = 0; i < ND; i++) { dp[i * 3 + 1] += 0.012; if (dp[i * 3 + 1] > 6) dp[i * 3 + 1] = 0; }
    dgeo.attributes.position.needsUpdate = true;
    callouts.forEach((s, i) => { const on = Math.min(1, Math.max(0, (c - 3.2 - i * 0.7) * 1.5)) * (c < 12.5 ? 1 : Math.max(0, 1 - (c - 12.5) * 2)); (s.material as import("three").SpriteMaterial).opacity = on; s.position.y += Math.sin(t * 1.2 + i) * 0.0015; });
    R.render(S, cam);
    if (!still) raf = requestAnimationFrame(frame);
  };
  resize();
  const ro = new ResizeObserver(resize); ro.observe(host);
  window.addEventListener("pointermove", onMove);
  const vis = () => { cancelAnimationFrame(raf); if (!document.hidden) raf = requestAnimationFrame(frame); };
  document.addEventListener("visibilitychange", vis);
  raf = requestAnimationFrame(frame);
  return () => {
    cancelAnimationFrame(raf); ro.disconnect(); window.removeEventListener("pointermove", onMove); document.removeEventListener("visibilitychange", vis);
    S.traverse((o) => { const m = o as import("three").Mesh; m.geometry?.dispose?.(); const mat = m.material as import("three").Material | import("three").Material[] | undefined; (Array.isArray(mat) ? mat : mat ? [mat] : []).forEach((x) => x.dispose()); });
    R.dispose();
  };
}
