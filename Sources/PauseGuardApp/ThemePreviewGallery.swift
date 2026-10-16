import AppKit
import SwiftUI
import PauseGuardImages

private struct PreviewRequest: Equatable {
    let imageIDs: [UUID]
    let assets: [ImageAsset]
    let singleImage: Bool
    let aspectRatio: Double
}

struct ThemePreviewGallery: View {
    @ObservedObject var model: DesktopModel
    @Binding var theme: BreakTheme
    @State private var previews: [TemplatePreview] = []
    @State private var renderer: ThemePreviewRenderer?
    @State private var loading = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    private var aspectRatio: Double {
        guard let size = NSScreen.screens.first?.frame.size, size.width > 0, size.height > 0 else { return 16.0 / 9 }
        return max(0.2, min(5, size.width / size.height))
    }
    private var request: PreviewRequest {
        PreviewRequest(imageIDs: theme.imageIDs, assets: model.assets,
            singleImage: model.preferences.singleImage, aspectRatio: aspectRatio)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("预览全部模板").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("使用当前尚未保存的图片选择。点击模板只更新草稿，返回编辑器后点“保存”才会生效。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { theme.layoutMode = .random } label: {
                    Label("随机模板", systemImage: theme.layoutMode == .random ? "checkmark.circle.fill" : "shuffle")
                }
                Text("随机模式会在每次休息时从以下五种模板中选择；预览不会改变下次休息。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                ProgressView("正在生成图片预览…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure {
                ContentUnavailableView("无法预览", systemImage: "photo", description: Text(failure))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(previews, id: \.layout) { preview in
                            Button { theme.layoutMode = preview.layout } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    BreakPreviewScene(image: preview.image, aspectRatio: Double(preview.image.width) / Double(preview.image.height),
                                        reduceVisualStimulation: model.preferences.reduceVisualStimulation)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    HStack {
                                        Text(preview.layout.title)
                                        Spacer()
                                        if theme.layoutMode == preview.layout { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                                    }.font(.headline)
                                }
                                .padding(10)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(theme.layoutMode == preview.layout ? Color.mint : .clear, lineWidth: 2) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择\(preview.layout.title)模板")
                            .accessibilityAddTraits(theme.layoutMode == preview.layout ? .isSelected : [])
                        }
                    }.padding(2)
                }
            }
            if model.preferences.singleImage { Text("已按“单张图片”偏好预览。多图布局会重复使用同一张图片。").font(.caption).foregroundStyle(.secondary) }
            if model.preferences.reduceVisualStimulation { Text("已启用减少视觉刺激，预览与休息画面均隐藏照片背景。").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(24)
        .frame(width: 920, height: 720)
        .task(id: request) {
            let request = request
            loading = true; failure = nil; previews = []
            let service = renderer ?? ThemePreviewRenderer(libraryURL: model.libraryURL)
            renderer = service
            do {
                let rendered = try await service.render(theme: theme, assets: request.assets,
                    singleImage: request.singleImage, aspectRatio: request.aspectRatio)
                try Task.checkCancellation()
                previews = rendered; loading = false
            } catch is CancellationError {
                // A newer draft owns the UI now, or the sheet has closed.
            } catch {
                guard !Task.isCancelled else { return }
                switch error {
                case ThemePreviewError.emptySelection: failure = "请先在图集编辑器中选择至少一张图片，再预览模板。"
                case ThemePreviewError.unavailableImages: failure = "所选图片已删除或无法读取。请返回编辑器重新选择图片。"
                default: failure = "图片预览生成失败，请返回编辑器检查图片后重试。"
                }
                loading = false
            }
        }
    }
}
