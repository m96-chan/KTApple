import CoreGraphics
import Foundation

/// Protocol abstracting visual overlay rendering for testability.
public protocol OverlayProvider: AnyObject {
    func showHighlight(frame: CGRect)
    func hideHighlight()
}
