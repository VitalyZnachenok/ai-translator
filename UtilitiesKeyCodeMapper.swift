//
//  KeyCodeMapper.swift
//  AI Translator
//
//  Маппинг клавиш на коды и символы
//

import Foundation

struct KeyCodeMapper {
    /// Разбирает метку клавиши (включая многосимвольные: "Space", "↩", "⇥", "⌫", "⎋"),
    /// в отличие от keyCodeForCharacter, который принимает только один символ.
    static func keyCodeForKeyLabel(_ label: String) -> UInt16 {
        switch label {
        case "Space", "␣", " ": return 0x31
        case "↩": return 0x24
        case "⇥": return 0x30
        case "⌫": return 0x33
        case "⎋": return 0x35
        default:
            if let last = label.last {
                return keyCodeForCharacter(last)
            }
            return 0x11
        }
    }

    static func keyCodeForCharacter(_ char: Character) -> UInt16 {
        switch char.uppercased() {
        case "A": return 0x00
        case "S": return 0x01
        case "D": return 0x02
        case "F": return 0x03
        case "H": return 0x04
        case "G": return 0x05
        case "Z": return 0x06
        case "X": return 0x07
        case "C": return 0x08
        case "V": return 0x09
        case "B": return 0x0B
        case "Q": return 0x0C
        case "W": return 0x0D
        case "E": return 0x0E
        case "R": return 0x0F
        case "Y": return 0x10
        case "T": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "=": return 0x18
        case "9": return 0x19
        case "7": return 0x1A
        case "-": return 0x1B
        case "8": return 0x1C
        case "0": return 0x1D
        case "]": return 0x1E
        case "O": return 0x1F
        case "U": return 0x20
        case "[": return 0x21
        case "I": return 0x22
        case "P": return 0x23
        case "L": return 0x25
        case "J": return 0x26
        case "'": return 0x27
        case "K": return 0x28
        case ";": return 0x29
        case "\\": return 0x2A
        case ",": return 0x2B
        case "/": return 0x2C
        case "N": return 0x2D
        case "M": return 0x2E
        case ".": return 0x2F
        case "`": return 0x32
        case "↩": return 0x24
        case "⇥": return 0x30
        case "⌫": return 0x33
        case "⎋": return 0x35
        default: return 0x11 // T по умолчанию
        }
    }
    
    static func characterForKeyCode(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x32: return "`"
        case 0x24: return "↩"
        case 0x30: return "⇥"
        case 0x31: return "Space"
        case 0x33: return "⌫"
        case 0x35: return "⎋"
        default: return "?"
        }
    }
}
