//
//  StyleHelpers.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/5/22.
//

import Foundation
import SwiftUI

extension CGFloat {
    static let resultIconSize: CGFloat = 48
    static let resultSize: CGFloat = 256
}

class GaussStyle {
    // Result
    static let resultSize: CGFloat = 256
    static let resultIconSize: CGFloat = 48
    static let resultSpacing = 1
    
    // Rounded Rectangles
    static let cornerRadiusLarge: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8
    static var rectLarge: RoundedRectangle {
        return RoundedRectangle(cornerRadius: cornerRadiusLarge, style: .continuous)
    }
    static var rectSmall: RoundedRectangle {
        return RoundedRectangle(cornerRadius: cornerRadiusSmall, style: .continuous)
    }
}
