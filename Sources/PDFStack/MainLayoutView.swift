import PDFStackKit
import SwiftUI

struct MainLayoutView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HSplitView {
            SidebarView(appState: appState)
                .frame(minWidth: 240, maxWidth: 320)
            detail
        }
        .background(Pheno.chromeDeep)
    }

    @ViewBuilder
    private var detail: some View {
        if let selected = appState.selectedItem {
            PageGridView(appState: appState, item: selected)
                .frame(minWidth: 400)
        } else {
            Text("Select a document from the list to view its pages.")
                .font(.system(size: 13))
                .foregroundColor(Pheno.textDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Pheno.canvasBg)
        }
    }
}
