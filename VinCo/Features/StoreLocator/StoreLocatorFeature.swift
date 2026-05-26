import Foundation
import ComposableArchitecture

@Reducer
struct StoreLocatorFeature {

    @ObservableState
    struct State: Equatable {}

    enum Action {
        case dismiss
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}
