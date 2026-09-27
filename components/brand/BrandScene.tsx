"use client";
import { useEffect, useRef } from "react";
import { INDIA_DOTS, LAND_DOTS } from "./globe-dots";

/**
 * KMR brand scene, drawn live (no image or video files): circuit-grid space, a light streak that turns into
 * blue / gold particle waves, a rotating dotted globe with India in gold, glowing orbit rings, a gold particle
 * swirl and the KMR wordmark. Follows the sequence of the KMR brand film, then keeps moving gently.
 */
export function BrandScene({ compact = false }: { compact?: boolean }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const wrap = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const cv = canvas.current!, host = wrap.current!;
    const ctx = cv.getContext("2d")!;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const land = decode(LAND_DOTS), india = decode(INDIA_DOTS);
    let W = 0, H = 0, dpr = 1, raf = 0, start = performance.now(), mx = 0, my = 0;
    let stars: Star[] = [], traces: Trace[] = [], swirl: Swirl[] = [];

    const resize = () => {
      dpr = Math.min(2, window.devicePixelRatio || 1);
      W = host.clientWidth; H = host.clientHeight;
      cv.width = W * dpr; cv.height = H * dpr; cv.style.width = W + "px"; cv.style.height = H + "px";
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const n = Math.round(Math.min(180, (W * H) / 7000));
      stars = Array.from({ length: n }, () => ({ x: Math.random() * W, y: Math.random() * H, r: Math.random() * 1.4 + 0.3, v: Math.random() * 0.15 + 0.03, gold: Math.random() < 0.28, p: Math.random() * 6.28 }));
      traces = Array.from({ length: Math.round(W / 60) }, () => trace(W, H));
      swirl = Array.from({ length: 90 }, (_, i) => ({ a: (i / 90) * Math.PI * 2, r: 1.25 + Math.random() * 0.55, s: 0.25 + Math.random() * 0.5, z: Math.random() * 0.6 - 0.3, size: Math.random() * 1.8 + 0.4 }));
    };
    const onMove = (e: PointerEvent) => { const b = host.getBoundingClientRect(); mx = (e.clientX - b.left) / b.width - 0.5; my = (e.clientY - b.top) / b.height - 0.5; host.style.setProperty("--mx", mx.toFixed(3)); host.style.setProperty("--my", my.toFixed(3)); };

    const frame = (now: number) => {
      const t = reduce ? 6 : (now - start) / 1000;
      draw(ctx, W, H, t, mx, my, land, india, stars, traces, swirl, compact);
      if (!reduce) raf = requestAnimationFrame(frame);
    };
    resize();
    const ro = new ResizeObserver(resize); ro.observe(host);
    window.addEventListener("pointermove", onMove);
    const vis = () => { cancelAnimationFrame(raf); if (!document.hidden) raf = requestAnimationFrame(frame); };
    document.addEventListener("visibilitychange", vis);
    raf = requestAnimationFrame(frame);
    host.classList.add("play");
    return () => { cancelAnimationFrame(raf); ro.disconnect(); window.removeEventListener("pointermove", onMove); document.removeEventListener("visibilitychange", vis); };
  }, [compact]);

  return (
    <div ref={wrap} className={`kmr-scene${compact ? " compact" : ""}`} aria-hidden="true">
      <canvas ref={canvas} />
      <div className="kmr-lockup">
        <svg className="kmr-mark" viewBox="0 0 640 230" role="img" aria-label="KMR">
          <defs>
            <linearGradient id="kmrBlue" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#8fb8ff" /><stop offset=".35" stopColor="#2f6bdc" /><stop offset=".7" stopColor="#123f9e" /><stop offset="1" stopColor="#0a2560" />
            </linearGradient>
            <linearGradient id="kmrGold" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#fff1b8" /><stop offset=".3" stopColor="#f3c55a" /><stop offset=".68" stopColor="#c8901f" /><stop offset="1" stopColor="#8a5c0c" />
            </linearGradient>
            <linearGradient id="kmrSwoosh" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stopColor="#1b4fc4" stopOpacity="0" /><stop offset=".25" stopColor="#2f6bdc" /><stop offset=".7" stopColor="#f3c55a" /><stop offset="1" stopColor="#f3c55a" stopOpacity="0" />
            </linearGradient>
            <linearGradient id="kmrShine" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stopColor="#fff" stopOpacity="0" /><stop offset=".5" stopColor="#fff" stopOpacity=".75" /><stop offset="1" stopColor="#fff" stopOpacity="0" />
            </linearGradient>
            <clipPath id="kmrLetters"><text x="320" y="170" textAnchor="middle" className="kmr-letters">KMR</text></clipPath>
          </defs>
          {/* extrusion: stacked darker copies give the letters depth */}
          {[7, 6, 5, 4, 3, 2, 1].map((d) => (
            <text key={d} x={320 + d * 0.6} y={170 + d} textAnchor="middle" className="kmr-letters" fill={d > 4 ? "#040c1f" : "#0b1d44"} opacity={0.9}>KMR</text>
          ))}
          <text x="320" y="170" textAnchor="middle" className="kmr-letters">
            <tspan fill="url(#kmrBlue)">K</tspan><tspan fill="url(#kmrGold)">M</tspan><tspan fill="url(#kmrBlue)">R</tspan>
          </text>
          <g clipPath="url(#kmrLetters)"><rect className="kmr-shine" x="-200" y="0" width="160" height="230" fill="url(#kmrShine)" transform="skewX(-18)" /></g>
          <path className="kmr-swoosh" d="M70 196 C 220 236, 430 232, 590 150" fill="none" stroke="url(#kmrSwoosh)" strokeWidth="7" strokeLinecap="round" />
        </svg>
        <div className="kmr-name">KMR GROUP</div>
        <div className="kmr-sub"><span />OF COMPANIES<span /></div>
        <div className="kmr-tag">INNOVATE <i>•</i> INTEGRATE <i>•</i> ELEVATE</div>
      </div>
    </div>
  );
}

/* ---------------------------------------------------------------- drawing */
type Star = { x: number; y: number; r: number; v: number; gold: boolean; p: number };
type Trace = { pts: [number, number][]; speed: number; off: number };
type Swirl = { a: number; r: number; s: number; z: number; size: number };
const BLUE = "120,175,255", GOLD = "243,197,90";
const ease = (x: number) => (x <= 0 ? 0 : x >= 1 ? 1 : 1 - Math.pow(1 - x, 3));

function decode(a: number[]): [number, number][] {
  const out: [number, number][] = [];
  for (let i = 0; i < a.length; i += 2) out.push([(a[i] / 10) * Math.PI / 180, (a[i + 1] / 10) * Math.PI / 180]);
  return out;
}
function trace(W: number, H: number): Trace {
  let x = Math.random() * W, y = Math.random() * H;
  const pts: [number, number][] = [[x, y]];
  for (let i = 0; i < 4; i++) { if (i % 2) y += (Math.random() - 0.5) * 160; else x += (Math.random() - 0.5) * 220; pts.push([x, y]); }
  return { pts, speed: 0.08 + Math.random() * 0.12, off: Math.random() };
}

function draw(ctx: CanvasRenderingContext2D, W: number, H: number, t: number, mx: number, my: number,
  land: [number, number][], india: [number, number][], stars: Star[], traces: Trace[], swirl: Swirl[], compact: boolean) {
  // space
  const bg = ctx.createRadialGradient(W * 0.5, H * 0.42, 0, W * 0.5, H * 0.42, Math.max(W, H) * 0.8);
  bg.addColorStop(0, "#0e2a5c"); bg.addColorStop(0.45, "#081a3c"); bg.addColorStop(1, "#020816");
  ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);

  // perspective floor grid, scrolling towards the viewer
  const hz = H * 0.62, vx = W * 0.5 + mx * 40;
  ctx.lineWidth = 1;
  for (let i = -14; i <= 14; i++) {
    ctx.strokeStyle = `rgba(${BLUE},0.06)`;
    ctx.beginPath(); ctx.moveTo(vx, hz); ctx.lineTo(vx + i * W * 0.12, H); ctx.stroke();
  }
  for (let k = 0; k < 10; k++) {
    const f = ((k + (t * 0.35) % 1) / 10), y = hz + (H - hz) * f * f;
    ctx.strokeStyle = `rgba(${BLUE},${0.03 + f * 0.07})`;
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke();
  }
  // circuit traces with travelling pulses
  for (const tr of traces) {
    ctx.strokeStyle = `rgba(${BLUE},0.07)`; ctx.beginPath(); tr.pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y))); ctx.stroke();
    const seg = Math.floor(((t * tr.speed + tr.off) % 1) * (tr.pts.length - 1)), f = (((t * tr.speed + tr.off) % 1) * (tr.pts.length - 1)) % 1;
    const [ax, ay] = tr.pts[seg], [bx, by] = tr.pts[seg + 1];
    ctx.fillStyle = `rgba(${BLUE},0.55)`; ctx.beginPath(); ctx.arc(ax + (bx - ax) * f, ay + (by - ay) * f, 1.4, 0, 6.28); ctx.fill();
  }
  // stars / dust
  for (const s of stars) {
    s.y -= s.v; if (s.y < -4) { s.y = H + 4; s.x = Math.random() * W; }
    const a = 0.25 + 0.35 * Math.sin(t * 1.5 + s.p);
    ctx.fillStyle = `rgba(${s.gold ? GOLD : BLUE},${a})`; ctx.beginPath(); ctx.arc(s.x + mx * 12 * s.r, s.y + my * 8 * s.r, s.r, 0, 6.28); ctx.fill();
  }

  // opening: a light streak that breaks into blue / gold waves (first ~2.4 s)
  if (t < 2.6) {
    const p = ease(t / 1.1), fade = t < 1.6 ? 1 : 1 - (t - 1.6);
    for (let w = 0; w < 2; w++) {
      ctx.save(); ctx.globalCompositeOperation = "lighter"; ctx.lineWidth = 2; ctx.shadowBlur = 18;
      ctx.shadowColor = ctx.strokeStyle = `rgba(${w ? GOLD : BLUE},${0.8 * fade})`;
      ctx.beginPath();
      for (let x = 0; x <= W * p; x += 6) {
        const amp = t > 0.9 ? Math.min(1, (t - 0.9) * 1.5) * 38 : 0;
        const y = H * 0.44 + Math.sin(x / 70 + t * 5 + w * 2) * amp * Math.sin((x / W) * Math.PI);
        x ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      ctx.stroke(); ctx.restore();
    }
  }

  // globe
  const g = ease((t - 1.3) / 1.4);
  if (g <= 0) return;
  const R = Math.min(W, H) * (compact ? 0.3 : 0.25) * (0.85 + 0.15 * g);
  const cx = W * 0.5 + mx * 18, cy = H * (compact ? 0.44 : 0.38) + my * 12;
  const rot = t * 0.22 + mx * 0.4 - 1.2, tilt = 0.32 + my * 0.12;
  const sinT = Math.sin(tilt), cosT = Math.cos(tilt);
  ctx.save(); ctx.globalAlpha = g;
  const sph = ctx.createRadialGradient(cx - R * 0.35, cy - R * 0.4, R * 0.1, cx, cy, R * 1.05);
  sph.addColorStop(0, "rgba(60,120,230,0.35)"); sph.addColorStop(0.7, "rgba(15,45,110,0.35)"); sph.addColorStop(1, "rgba(5,15,40,0.1)");
  ctx.fillStyle = sph; ctx.beginPath(); ctx.arc(cx, cy, R, 0, 6.28); ctx.fill();
  ctx.strokeStyle = "rgba(120,175,255,0.35)"; ctx.lineWidth = 1.5; ctx.shadowBlur = 25; ctx.shadowColor = "rgba(80,150,255,0.6)"; ctx.stroke(); ctx.shadowBlur = 0;

  const rings = (front: boolean) => {
    for (let k = 0; k < 2; k++) {
      const rr = R * (1.38 + k * 0.2), ang = (k ? -0.42 : 0.28) + Math.sin(t * 0.3 + k) * 0.05, flat = k ? 0.32 : 0.26;
      const grad = ctx.createLinearGradient(cx - rr, cy, cx + rr, cy);
      grad.addColorStop(0, `rgba(${BLUE},0.1)`); grad.addColorStop(0.45, `rgba(${k ? GOLD : BLUE},0.95)`); grad.addColorStop(1, `rgba(${GOLD},0.2)`);
      const draw = ease((t - 1.6 - k * 0.4) / 1.2);
      ctx.save(); ctx.translate(cx, cy); ctx.rotate(ang); ctx.scale(1, flat);
      ctx.strokeStyle = grad; ctx.lineWidth = (front ? 3.2 : 1.6) / flat * 0.35; ctx.shadowBlur = 16; ctx.shadowColor = k ? "rgba(243,197,90,.8)" : "rgba(90,160,255,.9)";
      ctx.globalAlpha = g * (front ? 1 : 0.35);
      ctx.beginPath();
      front ? ctx.arc(0, 0, rr, 0, Math.PI * draw) : ctx.arc(0, 0, rr, Math.PI, Math.PI + Math.PI * draw);
      ctx.stroke();
      // comet riding the ring
      const ca = (t * (0.9 + k * 0.4)) % (Math.PI * 2);
      if ((Math.sin(ca) > 0) === front && draw >= 1) { ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(Math.cos(ca) * rr, Math.sin(ca) * rr, 3 / flat * 0.35, 0, 6.28); ctx.fill(); }
      ctx.restore();
    }
  };
  rings(false);

  const dots = (list: [number, number][], color: string, size: number, glow: boolean) => {
    for (const [lon, lat] of list) {
      const l = lon + rot, cl = Math.cos(lat);
      const x0 = cl * Math.sin(l), y0 = Math.sin(lat), z0 = cl * Math.cos(l);
      const y = y0 * cosT - z0 * sinT, z = y0 * sinT + z0 * cosT;
      if (z < -0.05) continue;
      const a = 0.25 + 0.75 * Math.max(0, z);
      ctx.fillStyle = `rgba(${color},${a})`;
      if (glow) { ctx.shadowBlur = 8; ctx.shadowColor = `rgba(${color},0.9)`; }
      ctx.beginPath(); ctx.arc(cx + x0 * R, cy - y * R, size * (0.6 + 0.5 * z), 0, 6.28); ctx.fill();
    }
    ctx.shadowBlur = 0;
  };
  dots(land, "150,195,255", R / 150, false);
  dots(india, GOLD, R / 125, true);

  // gold swirl around the globe
  const sw = ease((t - 2.2) / 1.5);
  if (sw > 0) {
    ctx.globalCompositeOperation = "lighter";
    for (const p of swirl) {
      const a = p.a + t * p.s, r = R * p.r;
      const x = cx + Math.cos(a) * r, y = cy + Math.sin(a) * r * 0.38 + p.z * R;
      ctx.fillStyle = `rgba(${GOLD},${0.55 * sw * (0.4 + 0.6 * Math.abs(Math.sin(a * 2 + t)))})`;
      ctx.beginPath(); ctx.arc(x, y, p.size, 0, 6.28); ctx.fill();
    }
    ctx.globalCompositeOperation = "source-over";
  }
  rings(true);
  ctx.restore();
}
