import SwiftUI

struct CommunityPanel: View {
    @Bindable var community: CommunityStore
    var glassNamespace: Namespace.ID
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Community")
                    .font(.headline)

                HStack {
                    Button {
                        onBack()
                        MenuBarPanelKeeper.keepOpen()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Usage")
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 10)
                        .padding(.vertical, 5)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .clipShape(Capsule())
                    .glassEffectID("community-back", in: glassNamespace)
                    .accessibilityLabel("Usage")

                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            CommunityView(community: community)
        }
    }
}
