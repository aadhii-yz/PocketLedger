<script lang="ts">
  import { Camera, X } from "lucide-svelte";
  import { onDestroy, tick } from "svelte";

  interface Props {
    onScan: (barcode: string) => void;
    disabled?: boolean;
    class?: string;
  }

  let { onScan, disabled = false, class: className = "" }: Props = $props();

  let isMobile = $state(false);
  let modalOpen = $state(false);
  let scanning = $state(false);
  let error = $state("");

  // videoEl must be $state so bind:this updates are tracked in runes mode
  let videoEl = $state<HTMLVideoElement | null>(null);
  let mediaStream: MediaStream | null = null;
  let detected = false;
  let zxingStop: (() => void) | null = null;
  let rafId: number | null = null;

  $effect(() => {
    isMobile = typeof navigator !== "undefined" && navigator.maxTouchPoints > 0;
  });

  async function openScanner() {
    error = "";
    detected = false;
    modalOpen = true;
    await tick(); // wait for {#if modalOpen} to mount the video element

    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: "environment" } },
      });
    } catch (e: any) {
      error =
        e.name === "NotAllowedError"
          ? "Camera permission denied. Please allow camera access and try again."
          : "Could not access the camera.";
      return;
    }

    if (!videoEl) return;

    // Always attach stream immediately so the feed appears right away
    videoEl.srcObject = mediaStream;
    await videoEl.play().catch(() => {});
    scanning = true;

    if ("BarcodeDetector" in window) {
      startNativeLoop();
    } else {
      await startZXing();
    }
  }

  function startNativeLoop() {
    const BD = (window as any).BarcodeDetector;
    const detector = new BD({
      formats: ["code_128", "ean_13", "ean_8", "code_39", "qr_code", "upc_a", "upc_e"],
    });

    async function detectFrame() {
      if (!scanning || detected || !videoEl) return;
      try {
        const codes = await detector.detect(videoEl);
        if (codes.length && !detected) {
          handleDetected(codes[0].rawValue);
          return;
        }
      } catch {}
      if (scanning && !detected) rafId = requestAnimationFrame(detectFrame);
    }

    rafId = requestAnimationFrame(detectFrame);
  }

  async function startZXing() {
    try {
      const { BrowserMultiFormatReader } = await import("@zxing/browser");
      if (!videoEl || !mediaStream) return;
      const reader = new BrowserMultiFormatReader();
      // ZXing will re-attach the stream to the video (same stream, no visible change)
      const ctrl = await reader.decodeFromStream(
        mediaStream as any,
        videoEl,
        (result, _err, c) => {
          if (result && !detected) {
            c.stop();
            handleDetected(result.getText());
          }
        }
      );
      zxingStop = () => ctrl.stop();
    } catch {
      error = "Barcode scanner failed to load.";
    }
  }

  function handleDetected(value: string) {
    detected = true;
    closeScanner();
    onScan(value);
  }

  function closeScanner() {
    scanning = false;
    detected = false;
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
    if (zxingStop) {
      zxingStop();
      zxingStop = null;
    }
    if (mediaStream) {
      mediaStream.getTracks().forEach((t) => t.stop());
      mediaStream = null;
    }
    modalOpen = false;
    error = "";
  }

  onDestroy(closeScanner);
</script>

{#if isMobile}
  <button
    type="button"
    onclick={openScanner}
    {disabled}
    aria-label="Scan barcode with camera"
    class="flex items-center justify-center shrink-0 {className}"
  >
    <Camera class="w-5 h-5" />
  </button>
{/if}

{#if modalOpen}
  <!-- Full-screen camera modal — only rendered on mobile -->
  <div class="fixed inset-0 z-50 bg-black flex flex-col" role="dialog" aria-modal="true">
    <!-- Header -->
    <div class="flex items-center justify-between px-5 py-4 shrink-0">
      <div class="text-white">
        <p class="font-semibold text-base">Scan Barcode</p>
        <p class="text-xs text-white/50">Point camera at barcode</p>
      </div>
      <button
        onclick={closeScanner}
        class="p-2 text-white hover:bg-white/10 rounded-full transition-colors"
        aria-label="Close scanner"
      >
        <X class="w-6 h-6" />
      </button>
    </div>

    <!-- Camera feed -->
    <div class="flex-1 relative overflow-hidden">
      <!-- svelte-ignore a11y_media_has_caption -->
      <video
        bind:this={videoEl}
        playsinline
        muted
        class="absolute inset-0 w-full h-full object-cover"
      ></video>

      <!-- Scan-frame overlay: box-shadow darkens everything outside the frame -->
      <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
        <div
          class="relative w-72 h-36 rounded-xl"
          style="box-shadow: 0 0 0 9999px rgba(0,0,0,0.55);"
        >
          <!-- Corner brackets -->
          <div class="absolute -top-0.5 -left-0.5 w-7 h-7 border-t-[3px] border-l-[3px] border-white rounded-tl-lg"></div>
          <div class="absolute -top-0.5 -right-0.5 w-7 h-7 border-t-[3px] border-r-[3px] border-white rounded-tr-lg"></div>
          <div class="absolute -bottom-0.5 -left-0.5 w-7 h-7 border-b-[3px] border-l-[3px] border-white rounded-bl-lg"></div>
          <div class="absolute -bottom-0.5 -right-0.5 w-7 h-7 border-b-[3px] border-r-[3px] border-white rounded-br-lg"></div>

          <!-- Animated scan line -->
          <div class="absolute inset-x-2 h-0.5 bg-white/70 rounded-full scan-line"></div>
        </div>
      </div>
    </div>

    <!-- Status -->
    <div class="px-5 py-4 shrink-0 text-center">
      {#if error}
        <p class="text-red-400 text-sm">{error}</p>
        <button onclick={closeScanner} class="mt-2 text-white/60 underline text-xs">Close</button>
      {:else}
        <p class="text-white/40 text-xs">{scanning ? "Scanning…" : "Starting camera…"}</p>
      {/if}
    </div>
  </div>
{/if}

<style>
  .scan-line {
    animation: scanline 2s ease-in-out infinite;
  }
  @keyframes scanline {
    0%   { top: 15%; }
    50%  { top: 75%; }
    100% { top: 15%; }
  }
</style>
