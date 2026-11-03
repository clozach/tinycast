import Foundation

@main
struct ExtensionPaginationTests {
    static func main() {
        var state = ExtensionPaginationState()
        func page(_ count: Int, query: String = "", last: String? = nil) -> ExtensionPaginationState.Page {
            .init(rootID: 1, query: query, count: count, firstID: "0", lastID: last ?? "\(count)")
        }
        func take(_ page: ExtensionPaginationState.Page, near: Bool = true,
                  more: Bool = true, loading: Bool = false) -> Bool {
            state.shouldRequest(page: page, nearEnd: near, hasMore: more, isLoading: loading)
        }
        precondition(!take(page(100), near: false), "No eager load above the edge")
        precondition(take(page(100)), "First end crossing requests the next batch")
        precondition(!take(page(100)), "Repeated geometry cannot duplicate the request")
        precondition(!take(page(100), loading: true), "Loading does not rearm the same page")
        precondition(!take(page(100)), "Empty response cannot spin a request loop")
        precondition(take(page(200)), "New appended page can request at its own edge")
        precondition(!take(page(300), more: false), "Exhaustion stops requests")
        precondition(take(page(100, query: "new")), "A replacement query owns fresh paging")
        precondition(take(page(100, query: "new", last: "other-category")), "Same size new category loads")
        precondition(!take(page(200), loading: true), "In-flight next page waits")
        precondition(take(page(200)), "Completed loading can page again")
        print("11 pagination edge and request-lifetime checks passed")
    }
}
