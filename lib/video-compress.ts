/**
 * Makes a phone video web-ready in the browser before upload: 720 × 1280 (Instagram-reel 9:16, centre-cropped),
 * H.264 MP4 where the browser can record it (Safari, Chrome, Edge), sound kept, bitrate chosen so the file stays
 * well under the 50 MB storage limit. iPhone HEVC / .mov / 4K files become something every phone and PC can play.
 * Runs in real time (a 30-second reel takes about 30 seconds); onProgress gets 0–100.
 */
const OUT_W = 720, OUT_H = 1280, TARGET_BYTES = 40 * 1024 * 1024, MAX_SECONDS = 180;

const MIME = ["video/mp4;codecs=avc1.42E01E,mp4a.40.2", "video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm"];

export function canCompressVideo(): boolean {
  return typeof window !== "undefined" && typeof MediaRecorder !== "undefined" && !!HTMLCanvasElement.prototype.captureStream;
}

/** Must be called straight from the file-picker's change event (phones only allow sound playback after a tap). */
export function compressVideo(file: File, onProgress: (pct: number) => void): Promise<File> {
  const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
  const audio = AC ? new AC() : null; audio?.resume();                       // inside the tap
  const url = URL.createObjectURL(file);
  const v = document.createElement("video");
  v.playsInline = true; v.preload = "auto"; v.src = url; v.setAttribute("playsinline", "");
  const first = v.play();                                                      // inside the tap: unlocks later play()
  first?.catch(() => {});

  return new Promise<File>((resolve, reject) => {
    let done = false;
    const fail = (m: string) => { if (done) return; done = true; cleanup(); reject(new Error(m)); };
    const cleanup = () => { try { v.pause(); } catch { /* */ } URL.revokeObjectURL(url); audio?.close().catch(() => {}); };
    const timer = setTimeout(() => fail("This video could not be read. Try exporting it again from your phone's Photos app."), 20000);

    v.addEventListener("error", () => fail("This video format cannot be read in this browser. Try Safari on the iPhone, or Chrome on a computer."), { once: true });
    v.addEventListener("loadedmetadata", async () => {
      clearTimeout(timer);
      v.pause(); v.currentTime = 0;
      const dur = v.duration;
      if (!isFinite(dur) || dur <= 0) return fail("This video has no length — try another file.");
      if (dur > MAX_SECONDS) return fail(`Keep the promo video under ${MAX_SECONDS / 60} minutes (this one is ${Math.round(dur)} seconds).`);

      const canvas = document.createElement("canvas"); canvas.width = OUT_W; canvas.height = OUT_H;
      const g = canvas.getContext("2d"); if (!g) return fail("This browser cannot prepare videos.");
      const stream = canvas.captureStream(30);
      if (audio) {
        try {                                                                  // the soundtrack, without playing it aloud
          const src = audio.createMediaElementSource(v), dest = audio.createMediaStreamDestination();
          src.connect(dest); dest.stream.getAudioTracks().forEach((t) => stream.addTrack(t));
        } catch { /* no sound track — record picture only */ }
      } else v.muted = true;

      const mime = MIME.find((m) => MediaRecorder.isTypeSupported(m)) ?? "";
      const vbps = Math.max(900_000, Math.min(4_000_000, Math.floor((TARGET_BYTES * 8) / dur) - 128_000));
      let rec: MediaRecorder;
      try { rec = new MediaRecorder(stream, { mimeType: mime || undefined, videoBitsPerSecond: vbps, audioBitsPerSecond: 128_000 }); }
      catch { return fail("This browser cannot prepare videos. Use Safari on the iPhone or Chrome on a computer."); }
      const chunks: Blob[] = [];
      rec.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
      rec.onstop = () => {
        if (done) return; done = true; cleanup();
        const type = (rec.mimeType || mime || "video/webm").split(";")[0];
        const blob = new Blob(chunks, { type });
        const name = file.name.replace(/\.[^.]+$/, "") + (type === "video/mp4" ? ".mp4" : ".webm");
        resolve(new File([blob], name, { type }));
      };

      // centre-crop the source into 9:16
      const sw = v.videoWidth, sh = v.videoHeight, scale = Math.max(OUT_W / sw, OUT_H / sh);
      const dw = sw * scale, dh = sh * scale, dx = (OUT_W - dw) / 2, dy = (OUT_H - dh) / 2;
      const draw = () => {
        g.drawImage(v, dx, dy, dw, dh);
        onProgress(Math.min(99, Math.round((v.currentTime / dur) * 100)));
        if (!v.ended && !done) {
          const rv = v as HTMLVideoElement & { requestVideoFrameCallback?: (cb: () => void) => number };
          if (rv.requestVideoFrameCallback) rv.requestVideoFrameCallback(draw); else requestAnimationFrame(draw);
        }
      };
      v.addEventListener("ended", () => { onProgress(100); setTimeout(() => rec.state !== "inactive" && rec.stop(), 150); }, { once: true });
      g.fillStyle = "#000"; g.fillRect(0, 0, OUT_W, OUT_H);
      rec.start(1000);
      try { await v.play(); } catch { return fail("The video could not start. Tap Choose video… again and keep this screen open."); }
      draw();
    }, { once: true });
  });
}
