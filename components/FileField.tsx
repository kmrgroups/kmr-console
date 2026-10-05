"use client";
import { useRef, useState } from "react";
import { startUpload } from "@/app/cms-actions";
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
          {st.phase === "done" && <p className="upok">✓ Uploaded ({st.file}). Click <b>Save changes</b> to publish it.</p>}
          {st.phase === "error" && <p className="uperr">{st.msg}</p>}
          {st.phase === "idle" && !val && value && <p className="upwarn">Will be removed when you save.</p>}
          <small className="muted">{help || (videoField ? "Any phone video. It is resized to 720 × 1280 (reel size) and made web-ready before upload — this takes about as long as the video." : kind === "image" ? "Shown on the website as uploaded — nothing is cropped. JPG, PNG or WebP up to 25 MB." : "Stored privately; opened with a link that expires. PDF or image up to 10 MB.")}</small>
        </div>
      </div>
    </div>
  );
}
