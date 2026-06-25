import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

/** WKWebView file:// loads fail when Vite adds crossorigin to module scripts. */
function stripCrossoriginForWebView() {
  return {
    name: "strip-crossorigin-for-webview",
    transformIndexHtml(html) {
      return html.replace(/\s+crossorigin(="[^"]*")?/g, "");
    },
  };
}

export default defineConfig({
  plugins: [react(), stripCrossoriginForWebView()],
  base: "./",
  build: {
    outDir: path.resolve(__dirname, "../MuseDrop/Resources/ExcalidrawHost"),
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks: undefined,
      },
    },
  },
});
