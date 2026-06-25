import React, { useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Excalidraw, exportToBlob, serializeAsJSON } from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";

function postToSwift(payload) {
  const handler = window.webkit?.messageHandlers?.museDrop;
  if (handler) {
    handler.postMessage(payload);
  } else if (window.museDropDebug) {
    console.log("[museDrop]", payload);
  }
}

function parseIncoming(data) {
  if (typeof data === "string") {
    try {
      return JSON.parse(data);
    } catch {
      return null;
    }
  }
  return data;
}

function App() {
  const apiRef = useRef(null);
  const saveTimerRef = useRef(null);
  const [theme, setTheme] = useState("light");
  const [accentColor, setAccentColor] = useState("#ff6b9d");
  const [initialData, setInitialData] = useState(null);
  const [readySent, setReadySent] = useState(false);

  const emitScene = useCallback(() => {
    const api = apiRef.current;
    if (!api) return;
    const elements = api.getSceneElements();
    const appState = api.getAppState();
    const files = api.getFiles();
    const json = serializeAsJSON(elements, appState, files, "database");
    postToSwift({ type: "sceneChanged", sceneJSON: json });
  }, []);

  const scheduleSave = useCallback(() => {
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(emitScene, 1200);
  }, [emitScene]);

  const handleAPI = useCallback((api) => {
    apiRef.current = api;
    if (!readySent) {
      setReadySent(true);
      postToSwift({ type: "ready" });
    }
  }, [readySent]);

  useEffect(() => {
    window.museDropBridge = {
      loadScene(message) {
        const msg = parseIncoming(message);
        if (!msg) return;
        if (msg.theme) setTheme(msg.theme === "dark" ? "dark" : "light");
        if (msg.accentColor) setAccentColor(msg.accentColor);
        if (msg.sceneJSON) {
          try {
            const data = JSON.parse(msg.sceneJSON);
            setInitialData({
              elements: data.elements || [],
              appState: {
                ...data.appState,
                viewBackgroundColor: msg.theme === "dark" ? "#1e1e1e" : "#ffffff",
              },
              files: data.files || {},
            });
            apiRef.current?.updateScene({
              elements: data.elements || [],
              appState: data.appState || {},
              captureUpdate: "NEVER",
            });
            if (data.files) {
              apiRef.current?.addFiles(Object.values(data.files));
            }
          } catch (e) {
            postToSwift({ type: "error", message: String(e) });
          }
        }
      },

      setTheme(message) {
        const msg = parseIncoming(message);
        if (msg?.theme) setTheme(msg.theme === "dark" ? "dark" : "light");
        if (msg?.accentColor) setAccentColor(msg.accentColor);
      },

      pushElements(message) {
        const msg = parseIncoming(message);
        if (!msg?.elements?.length || !apiRef.current) return;
        const existing = apiRef.current.getSceneElements();
        apiRef.current.updateScene({
          elements: [...existing, ...msg.elements],
          captureUpdate: "IMMEDIATELY",
        });
        scheduleSave();
      },

      async exportPNG() {
        const api = apiRef.current;
        if (!api) return;
        const elements = api.getSceneElements();
        const appState = { ...api.getAppState(), exportBackground: true };
        const files = api.getFiles();
        const blob = await exportToBlob({
          elements,
          appState,
          files,
          mimeType: "image/png",
          quality: 1,
        });
        const reader = new FileReader();
        reader.onload = () => {
          const base64 = reader.result.split(",")[1];
          postToSwift({ type: "exportComplete", format: "png", base64 });
        };
        reader.readAsDataURL(blob);
      },

      async exportThumbnail() {
        const api = apiRef.current;
        if (!api) return;
        const elements = api.getSceneElements();
        if (!elements.length) {
          postToSwift({ type: "thumbnailComplete", base64: null });
          return;
        }
        const appState = {
          ...api.getAppState(),
          exportBackground: true,
          exportPadding: 16,
        };
        const files = api.getFiles();
        const blob = await exportToBlob({
          elements,
          appState,
          files,
          mimeType: "image/png",
          quality: 0.85,
        });
        const reader = new FileReader();
        reader.onload = () => {
          const base64 = reader.result.split(",")[1];
          postToSwift({ type: "thumbnailComplete", base64 });
        };
        reader.readAsDataURL(blob);
      },

      exportJSON() {
        const api = apiRef.current;
        if (!api) return;
        const json = serializeAsJSON(
          api.getSceneElements(),
          api.getAppState(),
          api.getFiles(),
          "database"
        );
        postToSwift({ type: "exportComplete", format: "excalidraw", sceneJSON: json });
      },

      requestSave() {
        emitScene();
      },
    };

    return () => {
      delete window.museDropBridge;
    };
  }, [emitScene, scheduleSave]);

  const excalidrawTheme = theme === "dark" ? "dark" : "light";

  return (
    <div style={{ height: "100%", width: "100%" }}>
      <Excalidraw
        excalidrawAPI={handleAPI}
        initialData={initialData}
        theme={excalidrawTheme}
        onChange={scheduleSave}
        UIOptions={{
          canvasActions: {
            loadScene: false,
            saveToActiveFile: false,
            export: false,
            toggleTheme: false,
          },
        }}
        renderTopRightUI={() => null}
      />
      <style>{`
        .excalidraw .App-menu__left { --color-primary: ${accentColor}; }
        .excalidraw button.active { --color-primary: ${accentColor}; }
      `}</style>
    </div>
  );
}

createRoot(document.getElementById("root")).render(<App />);
