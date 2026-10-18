import Foundation
import CryptoKit

// Public-key-only verification: no Keychain access and no signing credentials.
guard CommandLine.arguments.count == 4,
      let signature = Data(base64Encoded: CommandLine.arguments[2]),
      let publicBytes = Data(base64Encoded: CommandLine.arguments[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicBytes),
      let payload = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      key.isValidSignature(signature, for: payload) else {
    fputs("Invalid update signature\n", stderr); exit(1)
}
print("Update signature verified")
