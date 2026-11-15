import UIKit

/// MK24: one set of haptics for the whole app (item 193), so the same kind of action always feels the same.
/// tap = a tick or toggle · success = something saved or finished · warning = undo / skip · heavy = a long-press opened something.
@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func heavy() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
