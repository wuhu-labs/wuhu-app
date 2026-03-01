#!/usr/bin/env swift

// sign-update.swift — Sign a file with an Ed25519 private key for Sparkle.
//
// Usage: swift sign-update.swift <file> <private-key-path>
// Output: base64-encoded Ed25519 signature (printed to stdout)

import CryptoKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("Usage: sign-update.swift <file> <private-key-path>\n", stderr)
  exit(1)
}

let filePath = CommandLine.arguments[1]
let keyPath = CommandLine.arguments[2]

guard let fileData = FileManager.default.contents(atPath: filePath) else {
  fputs("Error: cannot read file at \(filePath)\n", stderr)
  exit(1)
}

guard let keyBase64 = try? String(contentsOfFile: keyPath, encoding: .utf8)
  .trimmingCharacters(in: .whitespacesAndNewlines),
  let keyData = Data(base64Encoded: keyBase64)
else {
  fputs("Error: cannot read private key at \(keyPath)\n", stderr)
  exit(1)
}

do {
  let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
  let signature = try privateKey.signature(for: fileData)
  print(signature.base64EncodedString())
} catch {
  fputs("Error: \(error)\n", stderr)
  exit(1)
}
