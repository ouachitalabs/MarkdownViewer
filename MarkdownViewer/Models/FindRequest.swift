import Foundation

enum FindDirection: Equatable {
    case forward
    case backward
}

struct FindRequest: Equatable {
    let query: String
    let direction: FindDirection
    let token: UUID
    let reset: Bool
}
