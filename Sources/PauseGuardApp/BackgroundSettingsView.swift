import SwiftUI
import AppKit

struct BackgroundSettingsView: View {
    @ObservedObject var model: DesktopModel
    @State private var messages = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("图片数量", selection: Binding(get: { model.preferences.singleImage }, set: { model.preferences.singleImage = $0; model.savePreferences() })) {
                Text("多图自动合成").tag(false); Text("单图").tag(true)
            }.pickerStyle(.segmented)
            Text("无可用图片时使用深色默认背景。每次休息会从启用图集中随机选择图片和布局。").font(.callout).foregroundStyle(.secondary)
            HStack { Button("批量导入图片…", systemImage: "plus") { model.importImages() }; if model.busy { ProgressView().controlSize(.small) }; Text("\(model.assets.count) 张图片").foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 14) {
                ForEach(model.assets) { asset in
                    VStack {
                        ThumbnailView(url: model.libraryURL.appendingPathComponent(asset.thumbnailName))
                        Text("\(asset.width) × \(asset.height)").font(.caption2).foregroundStyle(.secondary)
                        Button("删除", role: .destructive) { model.removeImage(asset.id) }.font(.caption)
                    }
                }
            }.disabled(model.busy)
            Divider()
            Text("自定义休息文案").font(.headline)
            Text("每行一条，休息时随机展示；留空使用内置文案。").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $messages).font(.body).frame(height: 110).padding(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Button("保存文案") { model.preferences.customMessages = messages.components(separatedBy: .newlines); model.savePreferences(); messages = model.preferences.customMessages.joined(separator: "\n") }
        }.onAppear { messages = model.preferences.customMessages.joined(separator: "\n") }
    }
}
struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Color.gray.opacity(0.12).overlay(Image(systemName: "photo").foregroundStyle(.secondary)) }
        }.frame(width: 110, height: 78).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            .task(id: url) {
                let data = await Task.detached { try? Data(contentsOf: url) }.value
                guard !Task.isCancelled else { return }; image = data.flatMap(NSImage.init(data:))
            }
    }
}
