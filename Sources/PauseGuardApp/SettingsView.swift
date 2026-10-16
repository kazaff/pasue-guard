import SwiftUI
import PauseGuardCore

public struct SettingsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var controller: AppController
    @State private var section = Section.timing
    private enum Section: String, CaseIterable, Identifiable {
        case timing = "工作与休息", enforcement = "强制执行", background = "休息背景", themes = "主题图集", general = "通用设置"
        var id: Self { self }
        var icon: String { switch self { case .timing: "timer"; case .enforcement: "shield.lefthalf.filled"; case .background: "photo.on.rectangle"; case .themes: "square.grid.2x2"; case .general: "gearshape" } }
    }
    public init(model: DesktopModel) { self.model = model; controller = model.controller }
    public var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in Label(item.rawValue, systemImage: item.icon).tag(item) }
                .navigationTitle("PauseGuard").navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !model.preferences.onboardingComplete { OnboardingView(model: model) }
                    Text(section.rawValue).font(.largeTitle.bold())
                    if !model.editingAllowed { Label("休息结束后可修改设置。", systemImage: "lock.fill").foregroundStyle(.secondary) }
                    Group {
                        switch section {
                        case .timing: timing
                        case .enforcement: enforcement
                        case .background: BackgroundSettingsView(model: model)
                        case .themes: ThemeLibraryView(model: model)
                        case .general: GeneralSettingsView(model: model)
                        }
                    }.disabled(!model.editingAllowed)
                    if let error = model.error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 820, minHeight: 620)
    }
    private func binding<T>(_ key: WritableKeyPath<UserSettings, T>) -> Binding<T> {
        Binding(get: { controller.settings[keyPath: key] }, set: { value in
            guard model.editingAllowed else { return }; var settings = controller.settings; settings[keyPath: key] = value; controller.updateSettings(settings)
        })
    }
    private var timing: some View {
        VStack(alignment: .leading, spacing: 24) {
            Stepper("工作时长  \(Int(controller.settings.workDurationSeconds / 60)) 分钟", value: binding(\.workDurationSeconds), in: 300...10800, step: 300)
            Stepper("休息时长  \(Int(controller.settings.breakDurationSeconds / 60)) 分钟", value: binding(\.breakDurationSeconds), in: 60...3600, step: 60)
            Picker("计时方式", selection: binding(\.timerMode)) { Text("自然流逝时间").tag(TimerMode.elapsed); Text("实际活跃时间").tag(TimerMode.active) }.pickerStyle(.radioGroup)
            Text("活跃计时会扣除超过 60 秒的空闲时间。睡眠和锁屏不计入工作时间，离开满一次休息时长后重新开始工作周期。")
                .font(.callout).foregroundStyle(.secondary)
            Stepper("提前预告  \(Int(controller.settings.preBreakWarningSeconds)) 秒", value: binding(\.preBreakWarningSeconds), in: 0...60, step: 5)
            Text("预告设为 0 秒时关闭预告。预告中跳过会让下次休息翻倍，最高 60 分钟；完成完整休息后恢复。")
                .font(.caption).foregroundStyle(.secondary)
            Text("工作时长在下个工作周期生效；休息时长和严格模式在下次休息生效。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var enforcement: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("严格模式", isOn: binding(\.strictMode))
            Text("严格休息中无法提前结束、暂停或正常退出。所有显示器显示倒计时；紧急解除需等待 5 秒并输入 4 位验证码，完成后释放覆盖并暂停循环。")
            Text("系统强制退出、会话和辅助功能操作保持可用。覆盖与前台激活为尽力执行，无法保证隔离其他应用或系统界面。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
