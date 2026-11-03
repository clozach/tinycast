struct ExtensionPaginationState {
    struct Page: Equatable {
        let rootID: Int
        let query: String
        let count: Int
        let firstID: String?
        let lastID: String?
    }

    private var requested: Page?

    mutating func shouldRequest(
        page: Page, nearEnd: Bool, hasMore: Bool, isLoading: Bool
    ) -> Bool {
        guard hasMore else {
            requested = nil
            return false
        }
        guard nearEnd, !isLoading, requested != page else { return false }
        requested = page
        return true
    }
}
