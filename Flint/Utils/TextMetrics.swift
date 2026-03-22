//
//  TextMetrics.swift
//  Flint
//
//  Multilingual text counting utility
//

import Foundation
import NaturalLanguage

/// Utility for counting words and characters in multilingual text
struct TextMetrics {
    /// Count words in text, handling CJK and European languages appropriately
    /// - Parameter text: The text to count
    /// - Returns: Word count (for CJK languages, returns character count excluding whitespace)
    static func countWords(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        
        // Detect if text contains CJK characters
        let containsCJK = text.containsCJKCharacters
        
        if containsCJK {
            // For CJK text, count characters (excluding whitespace and punctuation)
            return text.unicodeScalars.filter { scalar in
                !CharacterSet.whitespacesAndNewlines.contains(scalar) &&
                !CharacterSet.punctuationCharacters.contains(scalar)
            }.count
        } else {
            // For non-CJK text, use NLTokenizer for accurate word counting
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            
            // Try to detect language for better tokenization
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            if let language = recognizer.dominantLanguage {
                tokenizer.setLanguage(language)
            }
            
            var wordCount = 0
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
                wordCount += 1
                return true
            }
            
            return wordCount
        }
    }
    
    /// Count characters in text
    /// - Parameter text: The text to count
    /// - Returns: Character count
    static func countCharacters(in text: String) -> Int {
        return text.count
    }
}

extension String {
    /// Check if the string contains CJK (Chinese, Japanese, Korean) characters
    var containsCJKCharacters: Bool {
        return self.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x4E00...0x9FFF).contains(value) ||  // CJK Unified Ideographs
                   (0x3040...0x309F).contains(value) ||  // Hiragana
                   (0x30A0...0x30FF).contains(value) ||  // Katakana
                   (0xAC00...0xD7A3).contains(value) ||  // Hangul Syllables
                   (0x1100...0x11FF).contains(value) ||  // Hangul Jamo
                   (0x3400...0x4DBF).contains(value) ||  // CJK Extensions A
                   (0x20000...0x2A6DF).contains(value)   // CJK Extensions B
        }
    }
}
