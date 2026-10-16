import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: DesktopModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("降低视觉刺激", isOn: Binding(get: { model.preferences.reduceVisualStimulation }, set: { model.preferences.reduceVisualStimulation = $0; model.savePreferences() }))
            Text("休息页使用纯深色背景。界面默认不使用动画，并遵循系统的降低透明度设置。").font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("登录时启动", isOn: Binding(get: { model.preferences.loginAtLaunch }, set: { model.setLoginAtLaunch($0) })).disabled(model.isDemo)
            Text("开启后安装当前用户的登录启动和守护组件。下次登录打开应用；当前会话主动退出后不会重启。演示模式不可开启。").font(.callout).foregroundStyle(.secondary)
            Divider()
            Label("照片和配置只保存在本机", systemImage: "internaldrive")
            Text("无需账户、网络或辅助功能权限。聚合空闲时长仅用于计时，不记录键盘内容。").font(.callout).foregroundStyle(.secondary)
            if model.isDemo { Text("当前为演示模式：独立临时数据，时间加速 15 倍。工作约 20 秒，休息约 4 秒；必须点击开始才会计时。").foregroundStyle(.orange) }
        }
    }
}
