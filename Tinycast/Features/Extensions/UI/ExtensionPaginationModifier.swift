import SwiftUI

struct ExtensionPaginationModifier: ViewModifier {
    private struct Visibility: Equatable {
        let page: ExtensionPaginationState.Page
        let nearEnd: Bool
    }

    let page: ExtensionPaginationState.Page
    let handler: String?
    let isLoading: Bool
    let dispatch: (String) -> Void
    @State private var visibility: Visibility?
    @State private var requests = ExtensionPaginationState()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Visibility.self) { geometry in
                Visibility(page: page,
                    nearEnd: geometry.visibleRect.maxY >= geometry.contentSize.height - 120)
            } action: { _, value in
                visibility = value
                requestNextPage()
            }
            .onChange(of: isLoading) { requestNextPage() }
            .onChange(of: handler) { requestNextPage() }
    }

    private func requestNextPage() {
        guard visibility?.page == page else { return }
        if requests.shouldRequest(
            page: page, nearEnd: visibility?.nearEnd == true,
            hasMore: handler != nil, isLoading: isLoading
        ), let handler {
            dispatch(handler)
        }
    }
}
