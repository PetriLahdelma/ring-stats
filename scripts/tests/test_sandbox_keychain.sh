#!/bin/bash
# Verifies that the app's real KeychainCredentialStore works inside the App
# Sandbox with the app's own entitlements, and that the sandbox permits the
# loopback OAuth listener. A probe binary is compiled from the production
# source, signed ad-hoc with native/RingStats.entitlements, and run sandboxed.
# It uses its own bundle identifier and Keychain service, never the app's.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-sandbox-probe.XXXXXX")"
PROBE_ID="com.digitaltableteur.ringstats.sandbox-probe"
CONTAINER="$HOME/Library/Containers/$PROBE_ID"
cleanup() {
  /bin/rm -rf "$WORK"
  /bin/rm -rf "$CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

cat > "$WORK/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$PROBE_ID</string>
  <key>CFBundleName</key><string>RingStatsSandboxProbe</string>
</dict></plist>
PLIST

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
import Network

struct ProbeValue: Codable, Sendable, Equatable {
    let secret: String
}

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        print("FAIL: \(message)")
        exit(1)
    }
    print("ok: \(message)")
}

check(NSHomeDirectory().contains("/Library/Containers/"), "process is confined to an App Sandbox container")

let service = "com.digitaltableteur.ringstats.sandbox-probe.\(UUID().uuidString)"
let legacy = FileManager.default.temporaryDirectory.appendingPathComponent("probe-legacy", isDirectory: true)
let store = KeychainCredentialStore(service: service, legacyDirectory: legacy)
let value = ProbeValue(secret: UUID().uuidString)
do {
    try store.save(value, account: "probe")
    check(try store.load(ProbeValue.self, account: "probe") == value, "Keychain item saved and read back inside the sandbox")
    try store.delete(account: "probe")
    check(try store.load(ProbeValue.self, account: "probe") == nil, "Keychain item deleted inside the sandbox")
} catch {
    print("FAIL: Keychain error inside the sandbox: \(error.localizedDescription)")
    exit(1)
}

let parameters = NWParameters.tcp
// A fixed port, like the app's callback, chosen away from 43828 so a running
// Ring Stats authorization is never disturbed.
let port = NWEndpoint.Port(rawValue: UInt16.random(in: 49_152...60_999))!
parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
let listener = try NWListener(using: parameters)
let ready = DispatchSemaphore(value: 0)
nonisolated(unsafe) var listenerState = "none"
listener.stateUpdateHandler = { state in
    switch state {
    case .ready: listenerState = "ready"; ready.signal()
    case .failed(let error): listenerState = "failed: \(error)"; ready.signal()
    case .waiting(let error): listenerState = "waiting: \(error)"; ready.signal()
    default: break
    }
}
// NWListener refuses to start (EINVAL) without a connection handler.
listener.newConnectionHandler = { $0.cancel() }
listener.start(queue: .global())
_ = ready.wait(timeout: .now() + 5)
listener.cancel()
check(listenerState == "ready", "loopback listener allowed by network.server (\(listenerState))")
SWIFT

/usr/bin/xcrun swiftc -O -swift-version 5 \
  "$PROJECT_DIR/Sources/RingStats/KeychainCredentialStore.swift" \
  "$WORK/main.swift" \
  -o "$WORK/probe" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$WORK/Info.plist"
/usr/bin/codesign --force --sign - \
  --identifier "$PROBE_ID" \
  --entitlements "$PROJECT_DIR/native/RingStats.entitlements" \
  "$WORK/probe"
/usr/bin/codesign -d --entitlements - "$WORK/probe" 2>/dev/null | /usr/bin/grep -q "com.apple.security.app-sandbox" \
  || { echo "FAIL: probe is not signed with the sandbox entitlement" >&2; exit 1; }

"$WORK/probe"
echo "Sandbox Keychain tests passed"
