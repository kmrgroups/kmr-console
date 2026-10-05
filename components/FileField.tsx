"use client";
import { useEffect, useRef, useState } from "react";
import { galleryVideos, startUpload } from "@/app/cms-actions";
import { canCompressVideo, compressVideo } from "@/lib/video-compress";

type Props = {
  section: string; name: string; label: string; kind: "image" | "document"; value: string;
  docLink?: string | null; help?: string; required?: boolean;
};
type State = { phase: "idle" | "preparing" | "uploading" | "done" | "error"; pct: number; msg?: string; file?: string };

const fmtSize = (n: number) => (n > 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
const isVideo = (u: string) => /\.(mp4|webm|mov)(\?|$)/i.test(u);
const READY_MB = 45;   // a phone MP4 under this size uploads as it is; anything else is prepared for the web first

/**
 * Photo / document field: shows the current file, uploads a new one straight to storage with a progress bar,
 * then shows "Uploaded ✓". The form's Save button waits until the upload has finished.
 */
export function FileField({ section, name, label, kind, value, docLink, help, required }: Props) {
  const [val, setVal] = useState(value);
  const [preview, setPreview] = useState<string | null>(null);
  const [st, setSt] = useState<State>({ phase: "idle", pct: 0 });
  const box = useRef<HTMLDivElement>(null);
  const picker = useRef<HTMLInputElement>(null);

  const videoField = /video_url$/.test(name);
  const posterName = name.replace(/video_url$/, "video_poster");
  const [lib, setLib] = useState<{ open: boolean; loading?: boolean; error?: string; items?: { id: string; title: string | null; url: string; poster: string | null; used_for: string | null }[] }>({ open: false });
  useEffect(() => {
    const on = (e: Event) => { const d = (e as CustomEvent<{ name: string; value: string }>).detail; if (d?.name === name && d.value) { setVal(d.value); setPreview(null); setSt({ phase: "done", pct: 100, file: "from the gallery" }); } };
    window.addEventListener("kmr-fill-field", on);
    return () => window.removeEventListener("kmr-fill-field", on);
  }, [name]);
  async function openLibrary() {
    setLib({ open: true, loading: true });
    const r = await galleryVideos();
    setLib({ open: true, error: r.error, items: r.items ?? [] });
  }
  function pick(it: { url: string; poster: string | null }) {
    setVal(it.url); setPreview(null); setSt({ phase: "done", pct: 100, file: "from the gallery" }); setLib({ open: false });
    if (it.poster) window.dispatchEvent(new CustomEvent("kmr-fill-field", { detail: { name: posterName, value: it.poster } }));
  }
  async function choose(picked: File) {
    let file = picked;
    if (picked.type.startsWith("video/") || /\.(mov|m4v|hevc|3gp|mkv)$/i.test(picked.name)) {
      const ready = picked.type === "video/mp4" && picked.size <= READY_MB * 1024 * 1024;
      if (!ready) {
        if (!canCompressVideo()) { setSt({ phase: "error", pct: 0, msg: "This browser cannot prepare videos. Use Safari on the iPhone or Chrome on a computer, or upload an MP4 under 45 MB." }); return; }
        setPreview(null);
        setSt({ phase: "preparing", pct: 0, file: `${picked.name} · ${fmtSize(picked.size)}` });
        try { file = await compressVideo(picked, (pct) => setSt((s) => ({ ...s, pct }))); }
        catch (e) { setSt({ phase: "error", pct: 0, msg: (e as Error).message }); return; }
        if (file.size > 49 * 1024 * 1024) { setSt({ phase: "error", pct: 0, msg: "Even after preparing, this video is over 50 MB. Please trim it to under 2 minutes." }); return; }
      }
    }
    setPreview(kind === "image" && file.type.startsWith("image/") ? URL.createObjectURL(file) : file.type.startsWith("video/") ? URL.createObjectURL(file) : null);
    setSt({ phase: "uploading", pct: 0, file: `${file.name} · ${fmtSize(file.size)}${file !== picked ? ` (from ${fmtSize(picked.size)})` : ""}` });
    const r = await startUpload({ section, field: name, name: file.name, type: file.type || "application/octet-stream", size: file.size });
    if (r.error || !r.signedUrl || !r.value) { setSt({ phase: "error", pct: 0, msg: r.error || "Could not upload." }); return; }
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", r.signedUrl);
    xhr.setRequestHeader("Content-Type", file.type || "application/octet-stream");
    xhr.setRequestHeader("x-upsert", "false");
    xhr.upload.onprogress = (e) => { if (e.lengthComputable) setSt((s) => ({ ...s, pct: Math.round((e.loaded / e.total) * 100) })); };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) { setVal(r.value!); setSt((s) => ({ ...s, phase: "done", pct: 100 })); }
      else setSt({ phase: "error", pct: 0, msg: `Upload failed (${xhr.status}). Please try again.` });
    };
    xhr.onerror = () => setSt({ phase: "error", pct: 0, msg: "Upload failed — check your internet connection and try again." });
    xhr.send(file);
  }

  const shown = preview || (kind === "image" ? val : null);
  return (
    <div className="field full" ref={box} data-uploading={st.phase === "uploading" || st.phase === "preparing" ? "1" : undefined}>
      <span>{label}{required && " *"}</span>
      <input type="hidden" name={name} value={val} />
      <div className="filefield">
        <div className={`filefield-preview${kind === "document" ? " doc" : ""}`}>
          {kind === "image"
            ? (shown ? (isVideo(shown) || shown.startsWith("blob:") && videoField ? <video src={shown} muted playsInline controls style={{ width: "100%", height: "100%", objectFit: "contain", background: "#000" }} /> : <img src={shown} alt="" />) : <small className="muted">{videoField ? "No video" : "No photo"}</small>)
            : (val ? <a href={docLink ?? "#"} target="_blank" rel="noopener" className="btn secondary small">Open file</a> : <small className="muted">No file</small>)}
        </div>
        <div className="filefield-body">
          <div className="row" style={{ gap: 8 }}>
            <button type="button" className="btn secondary small" disabled={st.phase === "uploading" || st.phase === "preparing"} onClick={() => picker.current?.click()}>
              {val || preview ? "Replace…" : videoField ? "Choose video…" : kind === "image" ? "Choose photo…" : "Choose file…"}
            </button>
            {videoField && section !== "gallery" && (
              <button type="button" className="btn secondary small" disabled={st.phase === "uploading" || st.phase === "preparing"} onClick={openLibrary}>Choose from gallery…</button>
            )}
            {val && st.phase !== "uploading" && st.phase !== "preparing" && (
              <button type="button" className="btn ghost small" onClick={() => { setVal(""); setPreview(null); setSt({ phase: "idle", pct: 0 }); }}>Remove</button>
            )}
          </div>
          <input ref={picker} type="file" hidden accept={videoField ? "video/*" : kind === "image" ? "image/*" : "application/pdf,image/*"}
            onChange={(e) => { const f = e.target.files?.[0]; if (f) choose(f); e.target.value = ""; }} />
          {st.phase === "preparing" && (
            <div className="upbar" role="progressbar" aria-valuenow={st.pct} aria-valuemin={0} aria-valuemax={100}>
              <div style={{ width: `${Math.max(3, st.pct)}%` }} /><span>Preparing the video for the web {st.pct}% — keep this screen open ({st.file})</span>
            </div>
          )}
          {st.phase === "uploading" && (
            <div className="upbar" role="progressbar" aria-valuenow={st.pct} aria-valuemin={0} aria-valuemax={100}>
              <div style={{ width: `${Math.max(3, st.pct)}%` }} /><span>Uploading {st.pct}% — {st.file}</span>
            </div>
          )}
          {st.phase === "done" && <p className="upok">{st.file === "from the gallery" ? <>✓ Chosen from the gallery.</> : <>✓ Uploaded ({st.file}).</>} Click <b>Save changes</b> to publish it.</p>}
          {lib.open && (
            <div className="gallerypick" role="dialog" aria-modal="true" aria-label="Choose a video from the gallery" onClick={() => setLib({ open: false })}>
              <div className="gallerypick-box" onClick={(e) => e.stopPropagation()}>
                <div className="spread"><b>Choose a video from the gallery</b><button type="button" className="btn ghost small" onClick={() => setLib({ open: false })}>Close</button></div>
                <p className="muted" style={{ fontSize: 12.5, margin: "4px 0 10px" }}>Every promo video uploaded for an app, business, product or programme is kept here (Website CMS › Gallery). Picking one also fills its thumbnail.</p>
                {lib.loading ? <p className="muted">Loading…</p> : lib.error ? <div className="alert error">{lib.error}</div> : !lib.items?.length
                  ? <p className="muted">No videos in the gallery yet. Upload one here with <b>Choose video…</b> — it is added to the gallery when you save.</p>
                  : <div className="gallerypick-grid">{lib.items.map((it) => (
                      <button type="button" key={it.id} className={`gallerypick-item${it.url === val ? " on" : ""}`} onClick={() => pick(it)}>
                        <span className="gallerypick-media">{it.poster ? <img src={it.poster} alt="" loading="lazy" /> : <video src={`${it.url}#t=0.5`} muted playsInline preload="metadata" />}<i>▶</i></span>
                        <span className="gallerypick-t">{it.title || "Video"}</span>
                        {it.used_for && <small className="muted">{it.used_for}</small>}
                      </button>))}</div>}
              </div>
            </div>
          )}
          {st.phase === "error" && <p className="uperr">{st.msg}</p>}
          {st.phase === "idle" && !val && value && <p className="upwarn">Will be removed when you save.</p>}
          <small className="muted">{help || (videoField ? "Any phone video. It is resized to 720 × 1280 (reel size) and made web-ready before upload — this takes about as long as the video." : kind === "image" ? "Shown on the website as uploaded — nothing is cropped. JPG, PNG or WebP up to 25 MB." : "Stored privately; opened with a link that expires. PDF or image up to 10 MB.")}</small>
        </div>
      </div>
    </div>
  );
}
