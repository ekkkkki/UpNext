import SwiftUI
import AppKit
import QuickAddCore

/// Native vibrancy background for the floating panel.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// A small colored token chip used in the parse preview.
struct Chip: View {
    var text: String
    var systemImage: String?
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// Keyboard hint like `↩ Add`.
struct KeyHint: View {
    var key: String
    var label: String
    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct PriorityFlag: View {
    var priority: Priority
    var body: some View {
        if priority != .none {
            Image(systemName: "flag.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.priorityColor(priority))
        }
    }
}

extension Priority {
    var localizedName: String {
        switch self {
        case .none: return L("None", "无", "なし")
        case .low: return L("Low", "低", "低")
        case .medium: return L("Medium", "中", "中")
        case .high: return L("High", "高", "高")
        }
    }
}
