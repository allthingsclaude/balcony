import SwiftUI

/// Glass material popup for picking project files triggered by "@".
struct FilePickerMenu: View {
    let files: [String]
    let query: String
    let onSelect: (String) -> Void

    private var filteredFiles: [String] {
        if query.isEmpty { return Array(files.prefix(50)) }
        let lower = query.lowercased()
        return files.filter { $0.lowercased().contains(lower) }.prefix(50).map { $0 }
    }

    var body: some View {
        if filteredFiles.isEmpty {
            EmptyView()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredFiles, id: \.self) { file in
                        Button {
                            BalconyTheme.hapticLight()
                            onSelect(file)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: iconForFile(file))
                                    .font(.system(size: 12))
                                    .foregroundStyle(BalconyTheme.textSecondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fileName(file))
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(BalconyTheme.textPrimary)
                                        .lineLimit(1)

                                    let dir = directoryPath(file)
                                    if !dir.isEmpty {
                                        Text(dir)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(BalconyTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
            .modifier(LiquidGlassCapsule())
        }
    }

    // MARK: - Helpers

    private func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func directoryPath(_ path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir == "." ? "" : dir
    }

    private func iconForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "toml": return "gearshape"
        case "md", "txt", "rst": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "css", "scss", "less": return "paintpalette"
        case "html": return "globe"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "rb": return "diamond"
        case "rs": return "gearshape.2"
        case "go": return "arrow.right.circle"
        case "sh", "bash", "zsh": return "terminal"
        default: return "doc"
        }
    }
}
