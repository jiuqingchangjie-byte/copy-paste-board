import Foundation

/// Physical macOS key code plus a platform-neutral set of four modifiers.
public struct KeyboardShortcut: Codable, Equatable, Hashable {
    public struct Modifiers: OptionSet, Codable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let control = Self(rawValue: 1)
        public static let option = Self(rawValue: 2)
        public static let shift = Self(rawValue: 4)
        public static let command = Self(rawValue: 8)
    }
    public let keyCode: UInt32
    public let modifiers: Modifiers
    public init(keyCode: UInt32, modifiers: Modifiers) { self.keyCode = keyCode; self.modifiers = modifiers }
    public static let `default` = Self(keyCode: 9, modifiers: .option)
    public var isValid: Bool {
        Self.keyNames[keyCode] != nil && modifiers.rawValue & ~UInt32(15) == 0
            && !modifiers.intersection([.command, .control, .option]).isEmpty
    }
    public var displayName: String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
            + (Self.keyNames[keyCode] ?? "?")
    }
    // Stable key-position labels. Keyboard layout changes do not alter the binding.
    public static let keyNames: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",
        22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",
        32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",
        42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",
        65:"小键盘 .",67:"小键盘 *",69:"小键盘 +",75:"小键盘 /",76:"小键盘 ↩",78:"小键盘 −",
        81:"小键盘 =",82:"小键盘 0",83:"小键盘 1",84:"小键盘 2",85:"小键盘 3",86:"小键盘 4",
        87:"小键盘 5",88:"小键盘 6",89:"小键盘 7",91:"小键盘 8",92:"小键盘 9",
        96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",
        111:"F12",118:"F4",120:"F2",122:"F1",115:"Home",116:"Page Up",117:"⌦",
        119:"End",121:"Page Down",123:"←",124:"→",125:"↓",126:"↑"
    ]
}
