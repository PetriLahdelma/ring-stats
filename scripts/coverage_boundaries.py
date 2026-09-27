"""Groups llvm-cov JSON line coverage by architectural boundary."""
import json, sys
boundaries = [
    ("App shell (AppKit)", ["RingStatsApp.swift"]),
    ("Views (SwiftUI)", ["/Views/"]),
    ("View model", ["AppViewModel.swift"]),
    ("Oura API", ["OuraAPI.swift"]),
    ("OAuth", ["OAuthClient.swift"]),
    ("Callback listener", ["CallbackServer.swift"]),
    ("Keychain", ["KeychainCredentialStore.swift"]),
    ("Models", ["Models.swift", "Networking.swift"]),
    ("Diagnostics", ["Diagnostics.swift"]),
]
totals = {name: [0, 0] for name, _ in boundaries}
for entry in json.load(sys.stdin)["data"][0]["files"]:
    path = entry["filename"]
    lines = entry["summary"]["lines"]
    for name, needles in boundaries:
        if any(needle in path for needle in needles):
            totals[name][0] += lines["covered"]
            totals[name][1] += lines["count"]
            break
print("Boundary".ljust(22), "Lines".rjust(7), "Covered".rjust(8))
for name, _ in boundaries:
    covered, count = totals[name]
    percent = 100 * covered / count if count else 0
    print(f"{name:<22} {count:>7} {percent:>7.1f}%")
