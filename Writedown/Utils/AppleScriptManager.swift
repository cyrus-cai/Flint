//
//  AppleNotesHelper.swift
//  Writedown
//
//  Created by LC John on 2/7/25.
//

import Foundation
import AppKit

struct AppleScriptManager {
    static func createNewNote(with content: String) {
        // 为了防止双引号引起问题，将内容中的双引号进行转义
        let escapedContent = content.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptSource = """
        tell application "Notes"
            activate
            set newNote to make new note with properties {body:"\(escapedContent)"}
        end tell
        """
        if let script = NSAppleScript(source: appleScriptSource) {
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
            if let error = errorDict {
                print("AppleScript error: \(error)")
            }
        }
    }
}
