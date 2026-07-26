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
                        Label("Usage", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .glassEffect(.regular.interactive())
                    .glassEffectID("community-back", in: glassNamespace)

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
