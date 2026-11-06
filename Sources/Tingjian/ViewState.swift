import SwiftUI

/// The Command Line Tools ship without the SwiftUI macro plugin, and on the
/// macOS 26 SDK `@State` resolves to a macro. The underlying property-wrapper
/// type still works when spelled through an alias.
typealias ViewState = SwiftUI.State
