import SwiftUI

struct RootPanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var eventKit: EventKitService
    /// Use an opaque background instead of vibrancy (for offscreen screenshot rendering).
    var solidBackground = false

    private var needsPermission: Bool {
        !eventKit.remindersAuthorized || !eventKit.calendarAuthorized
    }

    var body: some View {
        VStack(spacing: 0) {
            if needsPermission && !solidBackground { permissionBanner }
            switch model.mode {
            case .add: AddView(model: model)
            case .search: SearchView(model: model)
            }
        }
        .frame(width: 640)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: model.mode)
        .animation(.easeOut(duration: 0.18), value: model.toast)
        .onExitCommand { model.onClose?() }
        .background(shortcutButtons)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if solidBackground {
            Color(nsColor: .windowBackgroundColor)
        } else {
            VisualEffectBackground()
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Access needed", "需要授权", "アクセスが必要")).font(.system(size: 12, weight: .semibold))
                Text(L("Allow Reminders & Calendar so UpNext can save items.",
                       "允许访问提醒事项和日历，UpNext 才能保存。",
                       "リマインダーとカレンダーへのアクセスを許可してください。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Grant Access", "授权", "許可")) { Task { await eventKit.requestAccess() } }
                .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private var shortcutButtons: some View {
        ZStack {
            Button("") { model.mode = .search }.keyboardShortcut("f", modifiers: .command)
            Button("") { model.mode = .add }.keyboardShortcut("n", modifiers: .command)
        }
        .hidden()
    }
}
