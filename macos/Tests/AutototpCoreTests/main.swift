import Foundation

// Minimal test harness: compiled together with Sources/AutototpCore by scripts/test.sh,
// so it runs with only the Swift compiler (no XCTest/SwiftPM needed).

var failures = 0
var currentTest = ""

func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #fileID, line: UInt = #line) {
    if !condition() {
        failures += 1
        print("  ✘ \(currentTest) – \(file):\(line)")
    }
}

func expectThrows<E: Error & Equatable>(_ expected: E, file: StaticString = #fileID, line: UInt = #line, _ body: () throws -> Void) {
    do {
        try body()
        failures += 1
        print("  ✘ \(currentTest) – expected \(expected), nothing thrown (\(file):\(line))")
    } catch let error as E where error == expected {
    } catch {
        failures += 1
        print("  ✘ \(currentTest) – expected \(expected), got \(error) (\(file):\(line))")
    }
}

func run(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    let before = failures
    do {
        try body()
    } catch {
        failures += 1
        print("  ✘ \(name) – threw \(error)")
    }
    print("\(failures == before ? "✔" : "✘") \(name)")
}

let totp = TOTPTests()
run("TOTP RFC 6238 SHA1", totp.rfc6238SHA1)
run("TOTP RFC 6238 SHA256/512", totp.rfc6238SHA256AndSHA512)
run("TOTP normalize/validate", totp.normalizesAndValidates)
run("TOTP format", totp.formatsCodes)
run("TOTP remaining seconds", totp.remainingSeconds)

let matcher = WindowMatcherTests()
run("Matcher case/punctuation", matcher.ignoresCaseAndPunctuation)
run("Matcher title match wins", matcher.windowTitleMatchWinsOverNameFallback)
run("Matcher name/issuer fallback", matcher.fallsBackToNameAndIssuer)

let imports = ImportTests()
run("Import otpauth lines", imports.parsesOtpAuthLines)
run("Import plain 2FAS", imports.parsesPlain2Fas)
run("Import encrypted 2FAS", imports.decryptsEncrypted2Fas)

let storage = StorageTests()
run("SecretBox round trip", storage.secretBoxRoundTrip)
run("Store reads sparse JSON", storage.readsWindowsStyleJSONWithMissingFields)
run("Store round trip", storage.storeRoundTrip)

print(failures == 0 ? "\nAlle Tests bestanden." : "\n\(failures) Fehler.")
exit(failures == 0 ? 0 : 1)
