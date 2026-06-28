pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Talks to a local (or remote) Ollama instance.
// Lists installed models, streams chat completions, and persists chat history.
Singleton {
    id: root

    // Override via OLLAMA_HOST env if you run Ollama elsewhere.
    readonly property string endpoint: (Quickshell.env("OLLAMA_HOST") || "http://127.0.0.1:11434").replace(/\/+$/, "")

    property list<var> models: []
    property string currentModel
    property bool available: false

    // Settings (persisted alongside chats)
    property int numCtx: 4096
    property real temperature: 0.8

    property bool responding: false
    property string streamContent: ""
    property string streamThinking: ""
    property string errorMsg: ""

    // Images (base64, no data: prefix) queued for the next message
    property list<string> pendingImages: []

    // All saved chats: { id, title, model, messages: [{role, content, images?}], updatedAt }
    property var chats: []
    property string currentChatId: ""

    // Live messages of the active chat (drives the ListView)
    readonly property ListModel messages: ListModel {}

    function reloadModels(): void {
        getModels.running = true;
    }

    function setModel(name: string): void {
        currentModel = name;
        const c = currentChat();
        if (c) {
            c.model = name;
            persist();
        }
    }

    function currentChat(): var {
        return chats.find(c => c.id === currentChatId) ?? null;
    }

    function newChat(): void {
        stop();
        // Reuse an existing empty chat instead of stacking blanks
        const cur = currentChat();
        if (cur && cur.messages.length === 0) {
            messages.clear();
            errorMsg = "";
            return;
        }
        const chat = {
            id: `${Date.now()}-${Math.floor(Math.random() * 1000)}`,
            title: qsTr("New chat"),
            model: currentModel,
            messages: [],
            updatedAt: Date.now()
        };
        chats = [chat, ...chats];
        currentChatId = chat.id;
        messages.clear();
        errorMsg = "";
        pendingImages = [];
        persist();
    }

    function loadChat(id: string): void {
        if (id === currentChatId)
            return;
        stop();
        saveCurrent();
        currentChatId = id;
        const c = currentChat();
        messages.clear();
        errorMsg = "";
        pendingImages = [];
        if (c) {
            if (c.model)
                currentModel = c.model;
            for (const m of c.messages)
                messages.append(m);
        }
    }

    function deleteChat(id: string): void {
        chats = chats.filter(c => c.id !== id);
        if (id === currentChatId) {
            if (chats.length > 0) {
                currentChatId = "";
                loadChat(chats[0].id);
            } else {
                currentChatId = "";
                newChat();
                return;
            }
        }
        persist();
    }

    function clear(): void {
        // Clear the current conversation (keeps the chat entry)
        stop();
        messages.clear();
        errorMsg = "";
        pendingImages = [];
        saveCurrent();
    }

    // Serialise the live ListModel back into the current chat + persist
    function saveCurrent(): void {
        let c = currentChat();
        if (!c) {
            if (messages.count === 0)
                return;
            c = {
                id: `${Date.now()}-${Math.floor(Math.random() * 1000)}`,
                title: qsTr("New chat"),
                model: currentModel,
                messages: [],
                updatedAt: Date.now()
            };
            chats = [c, ...chats];
            currentChatId = c.id;
        }
        const arr = [];
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i);
            const entry = {
                role: m.role,
                content: m.content
            };
            if (m.images && m.images.length)
                entry.images = m.images;
            arr.push(entry);
        }
        c.messages = arr;
        c.model = currentModel;
        c.updatedAt = Date.now();
        const firstUser = arr.find(m => m.role === "user");
        if (firstUser)
            c.title = firstUser.content.slice(0, 50).trim() || qsTr("New chat");
        chats = chats.slice().sort((a, b) => b.updatedAt - a.updatedAt);
        persist();
    }

    function persist(): void {
        storage.setText(JSON.stringify({
            chats,
            settings: {
                numCtx,
                temperature,
                currentModel
            }
        }, null, 0));
    }

    function attachImage(b64: string): void {
        pendingImages = [...pendingImages, b64];
    }

    function removePendingImage(idx: int): void {
        const arr = pendingImages.slice();
        arr.splice(idx, 1);
        pendingImages = arr;
    }

    function send(prompt: string): void {
        const text = prompt.trim();
        if ((!text && pendingImages.length === 0) || responding || !currentModel)
            return;

        if (!currentChat())
            newChat();

        errorMsg = "";
        const userMsg = {
            role: "user",
            content: text
        };
        if (pendingImages.length)
            userMsg.images = pendingImages.slice();
        messages.append(userMsg);
        pendingImages = [];

        const payload = [];
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i);
            const entry = {
                role: m.role,
                content: m.content
            };
            if (m.images && m.images.length)
                entry.images = Array.from(m.images);
            payload.push(entry);
        }

        streamContent = "";
        streamThinking = "";
        responding = true;
        saveCurrent();
        chat.command = ["curl", "-sN", "-X", "POST", `${endpoint}/api/chat`, "-H", "Content-Type: application/json", "-d", JSON.stringify({
                model: currentModel,
                messages: payload,
                stream: true,
                options: {
                    num_ctx: numCtx,
                    temperature: temperature
                }
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
        if (streamContent.length > 0) {
            messages.append({
                role: "assistant",
                content: streamContent
            });
            saveCurrent();
        }
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

    // Encodes a file to base64 for image attachments
    Process {
        id: encoder

        property string pendingPath

        command: ["base64", "-w", "0", pendingPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const b64 = text.trim();
                if (b64)
                    root.attachImage(b64);
            }
        }
    }

    function encodeAndAttach(path: string): void {
        encoder.pendingPath = path.replace(/^file:\/\//, "");
        encoder.running = true;
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/ai-chats.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.chats = data.chats ?? [];
                if (data.settings) {
                    if (data.settings.numCtx)
                        root.numCtx = data.settings.numCtx;
                    if (data.settings.temperature !== undefined)
                        root.temperature = data.settings.temperature;
                    if (data.settings.currentModel)
                        root.currentModel = data.settings.currentModel;
                }
                if (root.chats.length > 0) {
                    root.currentChatId = root.chats[0].id;
                    const c = root.currentChat();
                    for (const m of c.messages)
                        root.messages.append(m);
                }
            } catch (e) {
                root.chats = [];
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("{\"chats\":[]}"));
        }
    }
}
