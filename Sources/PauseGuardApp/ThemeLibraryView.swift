import SwiftUI
import PauseGuardImages

struct ThemeLibraryView: View {
    @ObservedObject var model: DesktopModel
    @State private var editing: BreakTheme?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("每次休息从启用的图集中随机挑选。图集可共用图片，删除图集不会删除原图。").font(.callout).foregroundStyle(.secondary)
            Button("创建图集", systemImage: "plus") { editing = BreakTheme(name: "新图集", imageIDs: []) }
            ForEach(model.themes) { theme in
                HStack(spacing: 14) {
                    Image(systemName: theme.enabled ? "photo.stack.fill" : "photo.stack").font(.title2).foregroundStyle(.mint)
                    VStack(alignment: .leading) { Text(theme.name).font(.headline); Text("\(theme.imageIDs.count) 张图片 · \(theme.layoutMode.title)").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Toggle("启用", isOn: Binding(get: { theme.enabled }, set: { enabled in var themes = model.themes; if let i = themes.firstIndex(where: { $0.id == theme.id }) { themes[i].enabled = enabled }; model.saveThemes(themes) })).labelsHidden().accessibilityLabel("启用 \(theme.name)")
                    Button("编辑") { editing = theme }
                    Button("删除", role: .destructive) { model.saveThemes(model.themes.filter { $0.id != theme.id }) }
                }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.themes.isEmpty { ContentUnavailableView("还没有图集", systemImage: "photo.stack", description: Text("先导入图片，或创建自己的主题图集。")) }
        }.disabled(model.busy).sheet(item: $editing) { theme in
            ThemeEditor(model: model, theme: theme) { value in
                var themes = model.themes
                if let i = themes.firstIndex(where: { $0.id == value.id }) { themes[i] = value } else { themes.append(value) }
                model.saveThemes(themes); editing = nil
            }
        }
    }
}
private struct ThemeEditor: View {
    @ObservedObject var model: DesktopModel
    @State var theme: BreakTheme
    @State private var previewing = false
    let save: (BreakTheme) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑图集").font(.title2.bold())
            TextField("图集名称", text: $theme.name)
            Toggle("启用图集", isOn: $theme.enabled)
            Picker("布局模板", selection: $theme.layoutMode) { ForEach(LayoutMode.allCases, id: \.self) { Text($0.title).tag($0) } }
            Button("预览全部模板", systemImage: "rectangle.grid.2x2") { previewing = true }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))]) {
                    ForEach(model.assets) { asset in
                        Button {
                            if theme.imageIDs.contains(asset.id) { theme.imageIDs.removeAll { $0 == asset.id } } else { theme.imageIDs.append(asset.id) }
                        } label: {
                            ThumbnailView(url: model.libraryURL.appendingPathComponent(asset.thumbnailName))
                                .overlay(alignment: .topTrailing) { Image(systemName: theme.imageIDs.contains(asset.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.white).padding(5).background(.black.opacity(0.3), in: Circle()) }
                        }.buttonStyle(.plain).accessibilityLabel("选择图片 \(asset.id)")
                    }
                }
            }.frame(height: 240)
            HStack { Button("取消") { dismiss() }; Spacer(); Button("保存") { theme.name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines); save(theme) }.buttonStyle(.borderedProminent).disabled(theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.editingAllowed) }
        }.padding(24).frame(width: 540)
            .sheet(isPresented: $previewing) { ThemePreviewGallery(model: model, theme: $theme) }
    }
}
extension LayoutMode {
    var title: String { switch self { case .hero: "主视觉"; case .grid: "网格"; case .collage: "拼贴"; case .cinematic: "电影感"; case .minimal: "极简"; case .random: "随机模板" } }
}
