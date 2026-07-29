import SwiftUI

struct ChangeLogView: View {
    let sections: [ChangeLogDisplaySection]
    var backTitle: String = "Settings"
    var glassNamespace: Namespace.ID
    var onBack: () -> Void

    private var headerVersion: String {
        sections.first(where: \.isHighlighted)?.version
            ?? sections.first?.version
            ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Change log")
                    .font(.headline)

                HStack {
                    Button {
                        onBack()
                        MenuBarPanelKeeper.keepOpen()
                    } label: {
                        Label(backTitle, systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .glassEffect(.regular.interactive())
                    .glassEffectID("changelog-back", in: glassNamespace)

                    Spacer()

                    if !headerVersion.isEmpty {
                        Text(headerVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                if sections.isEmpty {
                    Text("No release notes available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(sections) { section in
                            sectionBlock(section)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
        .onAppear { MenuBarPanelKeeper.keepOpen() }
    }

    @ViewBuilder
    private func sectionBlock(_ section: ChangeLogDisplaySection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle(section))
                .font(section.isHighlighted ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(section.isHighlighted ? Color.primary : Color.secondary)

            if section.items.isEmpty {
                Text("No notes for this version.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(item)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ section: ChangeLogDisplaySection) -> String {
        if section.isHighlighted {
            return "What's new in \(section.version)"
        }
        return section.version
    }
}
