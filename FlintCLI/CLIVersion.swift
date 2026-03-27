import Foundation

// Version is injected from Xcode build settings via GCC_PREPROCESSOR_DEFINITIONS
// or read from the Flint app bundle. Falls back to the project's MARKETING_VERSION.
let kFlintCLIVersion: String = {
    // Try reading from the installed Flint.app bundle first
    let appPlist = "/Applications/Flint.app/Contents/Info.plist"
    if let dict = NSDictionary(contentsOfFile: appPlist),
       let version = dict["CFBundleShortVersionString"] as? String {
        return version
    }
    // Fallback: compile-time constant synced by release.sh
    return "0.9.22"
}()
