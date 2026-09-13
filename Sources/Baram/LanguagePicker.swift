import SwiftUI

struct LanguagePickerButton: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let languages: [AppLanguage]
    let selectedID: String
    let allowsAuto: Bool
    let onSelect: (String) -> Void
    @State private var presented = false

    init(title: String, subtitle: String? = nil, symbol: String,
         languages: [AppLanguage], selectedID: String, allowsAuto: Bool,
         onSelect: @escaping (String) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.languages = languages
        self.selectedID = selectedID
        self.allowsAuto = allowsAuto
        self.onSelect = onSelect
    }

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BaramTheme.accentText)
                    .frame(width: 25, height: 25)
                    .background(BaramTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(BaramTheme.secondaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(BaramTheme.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(BaramButtonStyle())
        .background(BaramTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(BaramTheme.stroke.opacity(0.55)).allowsHitTesting(false))
        .accessibilityLabel(allowsAuto ? "원문 언어" : "번역 언어")
        .accessibilityValue(title)
        .help(allowsAuto ? "원문 언어 선택" : "번역 언어 선택")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            LanguagePickerPopover(languages: languages, selectedID: selectedID, allowsAuto: allowsAuto) { id in
                onSelect(id)
                presented = false
            }
        }
    }
}

private struct LanguagePickerPopover: View {
    let languages: [AppLanguage]
    let selectedID: String
    let allowsAuto: Bool
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    private let frequentIDs = ["ko", "en", "ja"]

    private var available: [AppLanguage] {
        var seen = Set<String>()
        return languages.filter { $0.id != "auto" && seen.insert($0.id).inserted }
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [AppLanguage] {
        let options = (allowsAuto ? [AppLanguage.auto] : []) + available
        return options.filter { language in
            [language.name, language.nativeName, language.id].contains { $0.localizedStandardContains(query) }
        }
    }
    private var frequent: [AppLanguage] {
        frequentIDs.compactMap { id in available.first { $0.id == id } }
    }
    private var remaining: [AppLanguage] { available.filter { !frequentIDs.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(BaramTheme.secondaryText)
                TextField("언어 검색", text: $search)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if !query.isEmpty, let first = matches.first { onSelect(first.id) } }
                    .accessibilityLabel("이름 또는 언어 코드로 검색")
                if !search.isEmpty {
                    Button { search = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(BaramTheme.secondaryText)
                            .frame(width: 20, height: 24)
                    }
                    .buttonStyle(BaramButtonStyle(compact: true))
                    .accessibilityLabel("검색 지우기")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(BaramTheme.raised, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)

            Rectangle().fill(BaramTheme.stroke.opacity(0.55)).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty {
                        if allowsAuto {
                            languageRow(.auto)
                            Rectangle().fill(BaramTheme.stroke.opacity(0.55)).frame(height: 1).padding(.vertical, 6)
                        }
                        if !frequent.isEmpty {
                            sectionTitle("자주 쓰는 언어")
                            ForEach(frequent) { languageRow($0) }
                        }
                        if !remaining.isEmpty {
                            sectionTitle("다른 언어").padding(.top, 9)
                            ForEach(remaining) { languageRow($0) }
                        }
                    } else if matches.isEmpty {
                        VStack(spacing: 7) {
                            Text("일치하는 언어가 없어요")
                                .font(.system(size: 12, weight: .medium))
                            Text("다른 이름이나 언어 코드로 검색해 보세요.")
                                .font(.system(size: 10)).foregroundStyle(BaramTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 46)
                    } else {
                        ForEach(matches) { languageRow($0) }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 270, height: 350)
        .background(BaramTheme.surface)
        .onAppear { searchFocused = true }
        .onExitCommand { dismiss() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(BaramTheme.secondaryText)
            .padding(.horizontal, 9).padding(.vertical, 4)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        let selected = language.id == selectedID
        return Button { onSelect(language.id) } label: {
            HStack(spacing: 9) {
                Group {
                    if language.id == "auto" { Image(systemName: "sparkle.magnifyingglass").font(.system(size: 12)) }
                    else { Text(badge(for: language.id)).font(.system(size: 11, weight: .medium)) }
                }
                .foregroundStyle(selected ? BaramTheme.accentText : BaramTheme.secondaryText)
                .frame(width: 26, height: 26)
                .background(selected ? BaramTheme.accent.opacity(0.12) : BaramTheme.raised,
                            in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.name).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    if language.nativeName != language.name {
                        Text(language.nativeName).font(.system(size: 10)).foregroundStyle(BaramTheme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(BaramTheme.accentText)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 41)
        }
        .buttonStyle(BaramButtonStyle(compact: true))
        .background(selected ? BaramTheme.accent.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .accessibilityLabel(language.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func badge(for id: String) -> String {
        switch id {
        case "ko": return "한"
        case "ja": return "あ"
        case "zh-Hans", "zh-Hant": return "文"
        default: return String(id.prefix(2)).uppercased()
        }
    }
}
