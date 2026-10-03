import AppKit

/// 系统语义色派生的单一来源（Render 层）。每个 token 保留身份色相，明度随外观解析。
enum NodeFillStyle {
    /// token 身份色相（HSB hue，0…1），取自原型 swatch 视觉锚。
    static let hue: [NodeFill: CGFloat] = [
        .sage: 0.34,   // 绿
        .sky: 0.57,    // 蓝
        .sand: 0.10,   // 暖金
        .rose: 0.01,   // 粉红
        .lilac: 0.74,  // 紫
    ]

    /// 工具条色点色。
    static func swatch(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.30, 0.82), dark: (0.40, 0.62))
    }

    /// 普通节点浅底。
    static func background(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.14, 0.94), dark: (0.24, 0.26))
    }

    /// 普通节点协调边框。
    static func border(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.20, 0.58), dark: (0.30, 0.52))
    }

    /// 中心主题深色变体（白字可读）。
    static func rootBackground(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.42, 0.30), dark: (0.38, 0.36))
    }

    /// 无填色根节点底（A/D token）：亮 = 深中性 #3a3a3c，暗 = accent 蓝 #0a84ff。
    static func rootDefault() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0x0A/255, green: 0x84/255, blue: 0xFF/255, alpha: 1)
                : NSColor(srgbRed: 0x3A/255, green: 0x3A/255, blue: 0x3C/255, alpha: 1)
        }
    }

    /// 连线（A/D token）：亮 #c7c7cc，暗 #3a3a3e。
    static func line() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0x3A/255, green: 0x3A/255, blue: 0x3E/255, alpha: 1)
                : NSColor(srgbRed: 0xC7/255, green: 0xC7/255, blue: 0xCC/255, alpha: 1)
        }
    }

    /// 画布底（A/D token）：亮 = 系统 windowBackgroundColor，暗 = #171719。
    static func canvasBackground() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0x17/255, green: 0x17/255, blue: 0x19/255, alpha: 1)
                : NSColor.windowBackgroundColor
        }
    }

    /// 由 token 色相 + 明度档（s, b）构造随外观解析的动态 NSColor。
    private static func appearanceAware(
        hue: CGFloat,
        light: (s: CGFloat, b: CGFloat),
        dark: (s: CGFloat, b: CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let pair = isDark ? dark : light
            return NSColor(hue: hue, saturation: pair.s, brightness: pair.b, alpha: 1)
        }
    }
}
