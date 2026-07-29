import SwiftUI

struct ChangeLogView: View {
    let version: String
    let items: [String]
    var backTitle: String = "Settings"
    var glassNamespace: Namespace.ID
    var onBack: () -> Void

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

                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's new in \(version)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if items.isEmpty {
                        Text("No release notes for this version.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(items, id: \.self) { item in
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
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .onAppear { MenuBarPanelKeeper.keepOpen() }
    }
}
