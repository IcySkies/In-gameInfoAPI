const assert = require("node:assert/strict");
const fs = require("node:fs");
const net = require("node:net");
const path = require("node:path");
const { once } = require("node:events");

async function connect(port) {
    const socket = net.createConnection({ host: "127.0.0.1", port });
    await once(socket, "connect");
    return socket;
}

function readFrames(socket, count) {
    return new Promise((resolve, reject) => {
        let buffer = Buffer.alloc(0);
        const frames = [];
        const timeout = setTimeout(() => finish(new Error("Timed out waiting for relay frames")), 5000);
        function finish(error) {
            clearTimeout(timeout);
            socket.off("data", onData);
            socket.off("error", finish);
            error ? reject(error) : resolve(frames);
        }
        function onData(chunk) {
            buffer = Buffer.concat([buffer, chunk]);
            while (buffer.length >= 4) {
                const length = buffer.readUInt32LE(0);
                if (buffer.length < 4 + length) return;
                frames.push(Buffer.from(buffer.subarray(0, 4 + length)));
                buffer = buffer.subarray(4 + length);
                if (frames.length === count) { finish(); return; }
            }
        }
        socket.on("data", onData);
        socket.on("error", finish);
    });
}

async function main() {
    const gamePath = process.argv[2];
    assert.ok(gamePath, "Pass the configured game directory");
    const discovery = JSON.parse(fs.readFileSync(path.join(gamePath, "AutoChartSwitchV2/bridge-relay.json"), "utf8"));
    assert.equal(discovery.gamePort, 28745);
    const chart = {
        chartId: "relay-stats-regression", title: "Stats Regression", artist: "Regression",
        rawDifficultyName: "FINALE", difficultyCode: "FINALE",
        techStats: { chip: 12.5, tech: 34, stream: 56.75, chord: 78, burst: 90, gimmick: 6 },
    };
    const frames = [
        { protocolVersion: "1.0", sequence: 1.0, kind: "ChartInfo", chart },
        { protocolVersion: 1.0, sequence: "2.0", kind: "Selection" },
    ].map(event => {
        const payload = Buffer.from(JSON.stringify(event) + "\0");
        const frame = Buffer.alloc(4 + payload.length);
        frame.writeUInt32LE(payload.length);
        payload.copy(frame, 4);
        return frame;
    });
    const sockets = [];
    try {
        for (let i = 0; i < 2; i++) sockets.push(await connect(discovery.subscriberPort));
        const reads = sockets.map(socket => readFrames(socket, frames.length));
        // Let the relay register both subscribers before publishing.
        await new Promise(resolve => setTimeout(resolve, 100));
        const producer = await connect(discovery.gamePort);
        sockets.push(producer);
        producer.write(Buffer.concat(frames));
        for (const received of await Promise.all(reads)) assert.deepEqual(received, frames);
        const replay = await connect(discovery.subscriberPort);
        sockets.push(replay);
        assert.deepEqual(await readFrames(replay, frames.length), frames);
        console.log("Relay preserved all six nonzero stats byte-for-byte for two subscribers and journal replay.");
    }
    finally { sockets.forEach(socket => socket.destroy()); }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
