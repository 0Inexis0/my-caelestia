pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Talks to a local (or remote) Ollama instance.
// Lists installed models and streams chat completions over the HTTP API.
Singleton {
    id: root

    // Override via OLLAMA_HOST env if you run Ollama elsewhere.
    readonly property string endpoint: (Quickshell.env("OLLAMA_HOST") || "http://127.0.0.1:11434").replace(/\/+$/, "")

    property list<var> models: []
    property string currentModel
    property bool available: false

    property bool responding: false
    property string streamContent: ""
    property string streamThinking: ""
    property string errorMsg: ""

    readonly property ListModel messages: ListModel {}

    function reloadModels(): void {
        getModels.running = true;
    }

    function setModel(name: string): void {
        currentModel = name;
    }

    function clear(): void {
        stop();
        messages.clear();
        errorMsg = "";
    }

    function send(prompt: string): void {
        const text = prompt.trim();
        if (!text || responding || !currentModel)
            return;

        errorMsg = "";
        messages.append({
            role: "user",
            content: text
        });

        const payload = [];
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i);
            payload.push({
                role: m.role,
                content: m.content
            });
        }

        streamContent = "";
        streamThinking = "";
        responding = true;
        chat.command = ["curl", "-sN", "-X", "POST", `${endpoint}/api/chat`, "-H", "Content-Type: application/json", "-d", JSON.stringify({
                model: currentModel,
                messages: payload,
                stream: true
            })];
        chat.running = true;
    }

    function stop(): void {
        if (chat.running)
            chat.running = false;
        finalise();
    }

    function finalise(): void {
        if (!responding)
            return;
        responding = false;
        if (streamContent.length > 0)
            messages.append({
                role: "assistant",
                content: streamContent
            });
        streamContent = "";
        streamThinking = "";
    }

    Process {
        id: getModels

        running: true
        command: ["curl", "-s", `${root.endpoint}/api/tags`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.models = (data.models ?? []).map(m => m.name).sort();
                    root.available = true;
                    if (!root.currentModel && root.models.length > 0)
                        root.currentModel = root.models[0];
                } catch (e) {
                    root.available = false;
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                root.available = false;
        }
    }

    Process {
        id: chat

        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (!trimmed)
                    return;
                try {
                    const obj = JSON.parse(trimmed);
                    if (obj.error) {
                        root.errorMsg = obj.error;
                        return;
                    }
                    if (obj.message?.thinking)
                        root.streamThinking += obj.message.thinking;
                    if (obj.message?.content)
                        root.streamContent += obj.message.content;
                } catch (e) {
                    // Ignore non-JSON keepalive lines
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.errorMsg = text.trim();
            }
        }
        onExited: code => {
            if (code !== 0 && !root.errorMsg)
                root.errorMsg = qsTr("Could not reach Ollama at %1").arg(root.endpoint);
            root.finalise();
        }
    }
}
