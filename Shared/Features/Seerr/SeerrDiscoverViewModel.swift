import Foundation
import Observation

@MainActor
@Observable
final class SeerrDiscoverViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let permissionService = SeerrPermissionService()

    var trending: [SeerrMedia] = []
    var popularMovies: [SeerrMedia] = []
    var popularTV: [SeerrMedia] = []
    var searchQuery = ""
    var searchResults: [SeerrMedia] = []
    var isSearching = false
    var isLoading = false
    var errorMessage: String?
    var pendingRequestsCount = 0

    init(store: SeerrStore) {
        self.store = store
    }

    var isLoggedIn: Bool {
        store.isLoggedIn
    }

    var hasContent: Bool {
        !trending.isEmpty || !popularMovies.isEmpty || !popularTV.isEmpty
    }

    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canManageRequests: Bool {
        permissionService.hasPermission(.manageRequests, user: store.user)
    }

    var shouldShowManageRequestsButton: Bool {
        canManageRequests && pendingRequestsCount > 0
    }

    func load() async {
        guard !isLoading else { return }
        guard let baseURL else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let repository = SeerrDiscoverRepository(baseURL: baseURL)
            let trendingPage = try await repository.getTrending(page: 1)
            let moviesPage = try await repository.discoverMovies(page: 1)
            let tvPage = try await repository.discoverTV(page: 1)

            trending = trendingPage.results
            popularMovies = moviesPage.results
            popularTV = tvPage.results
        } catch {
            errorMessage = String(localized: .init("common.errors.tryAgainLater"))
        }

        await loadRequestCount()
    }

    func search() async {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL else { return }

        if trimmedQuery.isEmpty {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let repository = SeerrDiscoverRepository(baseURL: baseURL)
            let response = try await repository.search(query: trimmedQuery, page: 1)
            guard !Task.isCancelled else { return }
            // Person results aren't handled yet in the UI.
            searchResults = response.results.filter { $0.mediaType != .person }
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled {
                return
            }
            errorMessage = String(localized: .init("common.errors.tryAgainLater"))
        }
    }

    func reload() async {
        trending = []
        popularMovies = []
        popularTV = []
        searchResults = []
        await load()
    }

    func makePendingRequestsViewModel() -> SeerrPendingRequestsViewModel? {
        guard baseURL != nil else { return nil }
        return SeerrPendingRequestsViewModel(store: store)
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private func loadRequestCount() async {
        guard canManageRequests else {
            pendingRequestsCount = 0
            return
        }
        guard let baseURL else { return }

        do {
            let repository = SeerrRequestRepository(baseURL: baseURL)
            let count = try await repository.getRequestCount()
            pendingRequestsCount = count.pending
        } catch {
            pendingRequestsCount = 0
        }
    }
}
