import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: DesktopModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "leaf.circle.fill").font(.system(size: 56)).foregroundStyle(.mint)
            Text("给专注留一点呼吸").font(.largeTitle.bold())
            Text("PauseGuard 会在工作结束后提醒你休息，并覆盖所有显示器。先配置下方的工作时长、执行方式和背景，再明确开始保护。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("严格模式仍保留系统紧急操作；休息内可确认紧急解除并暂停。", systemImage: "hand.raised")
                .font(.callout)
            Button("使用当前配置，开始保护") { model.start() }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
