"use client";
import { useRef, useState } from "react";
import { startUpload } from "@/app/cms-actions";

type Props = {
  section: string; name: string; label: string; kind: "image" | "document"; value: string;
  docLink?: string | null; help?: string; required?: boolean;
};
type State = { phase: "idle" | "uploading" | "done" | "error"; pct: number; msg?: string; file?: string };

const fmtSize = (n: number) => (n > 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
const isVideo = (u: string) => /\.(mp4|webm)(\?|$)/i.test(u);

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

  async function choose(file: File) {
    setPreview(kind === "image" && file.type.startsWith("image/") ? URL.createObjectURL(file) : null);
    setSt({ phase: "uploading", pct: 0, file: `${file.name} · ${fmtSize(file.size)}` });
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
    <div className="field full" ref={box} data-uploading={st.phase === "uploading" ? "1" : undefined}>
      <span>{label}{required && " *"}</span>
      <input type="hidden" name={name} value={val} />
      <div className="filefield">
        <div className={`filefield-preview${kind === "document" ? " doc" : ""}`}>
          {kind === "image"
            ? (shown ? (isVideo(shown) ? <video src={shown} muted /> : <img src={shown} alt="" />) : <small className="muted">No photo</small>)
            : (val ? <a href={docLink ?? "#"} target="_blank" rel="noopener" className="btn secondary small">Open file</a> : <small className="muted">No file</small>)}
        </div>
        <div className="filefield-body">
          <div className="row" style={{ gap: 8 }}>
            <button type="button" className="btn secondary small" disabled={st.phase === "uploading"} onClick={() => picker.current?.click()}>
              {val || preview ? "Replace…" : kind === "image" ? "Choose photo…" : "Choose file…"}
            </button>
            {val && st.phase !== "uploading" && (
              <button type="button" className="btn ghost small" onClick={() => { setVal(""); setPreview(null); setSt({ phase: "idle", pct: 0 }); }}>Remove</button>
            )}
          </div>
          <input ref={picker} type="file" hidden accept={kind === "image" ? "image/*,video/mp4,video/webm" : "application/pdf,image/*"}
            onChange={(e) => { const f = e.target.files?.[0]; if (f) choose(f); e.target.value = ""; }} />
          {st.phase === "uploading" && (
            <div className="upbar" role="progressbar" aria-valuenow={st.pct} aria-valuemin={0} aria-valuemax={100}>
              <div style={{ width: `${Math.max(3, st.pct)}%` }} /><span>Uploading {st.pct}% — {st.file}</span>
            </div>
          )}
          {st.phase === "done" && <p className="upok">✓ Uploaded ({st.file}). Click <b>Save changes</b> to publish it.</p>}
          {st.phase === "error" && <p className="uperr">{st.msg}</p>}
          {st.phase === "idle" && !val && value && <p className="upwarn">Will be removed when you save.</p>}
          <small className="muted">{help || (kind === "image" ? "Shown on the website as uploaded — nothing is cropped. JPG, PNG or WebP up to 25 MB." : "Stored privately; opened with a link that expires. PDF or image up to 10 MB.")}</small>
        </div>
      </div>
    </div>
  );
}
