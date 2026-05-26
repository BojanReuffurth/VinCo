import Foundation
import ComposableArchitecture
import SwiftUI

@Reducer
struct AppFeature {
    enum Tab: Hashable { case collection, wishlist }

    @ObservableState
    struct State: Equatable {
        var tab:         Tab               = .collection
        var collection:  CollectionFeature.State  = .init(isWishlist: false)
        var wishlist:    CollectionFeature.State  = .init(isWishlist: true)
        var stats:       StatsFeature.State       = .init()
        var settings:    SettingsFeature.State    = .init()
        @Presents var suggestions: SuggestionsFeature.State?
    }

    enum Action {
        case tabSelected(Tab)
        case collection(CollectionFeature.Action)
        case wishlist(CollectionFeature.Action)
        case stats(StatsFeature.Action)
        case settings(SettingsFeature.Action)
        case suggestions(PresentationAction<SuggestionsFeature.Action>)
        case suggestionsTapped
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.collection, action: \.collection) { CollectionFeature() }
        Scope(state: \.wishlist,   action: \.wishlist)   { CollectionFeature() }
        Scope(state: \.stats,      action: \.stats)      { StatsFeature() }
        Scope(state: \.settings,   action: \.settings)   { SettingsFeature() }
        Reduce { state, action in
            switch action {
            case .tabSelected(let t): state.tab = t;                     return .none
            case .suggestionsTapped:  state.suggestions = .init();       return .none
            default: return .none
            }
        }
        .ifLet(\.$suggestions, action: \.suggestions) { SuggestionsFeature() }
    }
}
