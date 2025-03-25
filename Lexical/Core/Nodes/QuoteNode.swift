/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

public class QuoteNode: ElementNode {
    override public init() {
        super.init()
    }

    override public required init(_ key: NodeKey?) {
        super.init(key)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    override public class func getType() -> NodeType {
        return .quote
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
    }

    override public func clone() -> Self {
        Self(key)
    }

    override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
        var attributeDictionary = super.getAttributedStringAttributes(theme: theme)
        if let quoteTheme = theme.quote {
            attributeDictionary.merge(quoteTheme) { _, new in new }
        } else {
            // a few defaults
            attributeDictionary[.paddingHead] = 4.0
            attributeDictionary[.paddingTail] = -4.0
        }

        if attributeDictionary[.quoteCustomDrawing] == nil {
            let customAttr = QuoteCustomDrawingAttributes(barColor: UIColor.gray, barWidth: 4, rounded: false, barInsets: UIEdgeInsets())
            attributeDictionary[.quoteCustomDrawing] = customAttr
        }

        return attributeDictionary
    }

    override public func getIndent() -> Int {
        0
    }

    // MARK: - Mutation

    override open func insertNewAfter(selection: RangeSelection?) throws -> ParagraphNode? {
        guard let selection else {
            return nil
        }

        let children = self.getChildren()
        let childrenLength = children.count

        if childrenLength >= 2 &&
            children.last is LineBreakNode &&
            children[childrenLength - 2] is LineBreakNode &&
            selection.isCollapsed() &&
            selection.anchor.key == self.key &&
            selection.anchor.offset == childrenLength
        {
            try children[childrenLength - 1].remove()
            try children[childrenLength - 2].remove()
            let newElement = createParagraphNode()
            try self.insertAfter(nodeToInsert: newElement)
            return newElement
        } else {
            return nil
        }
    }

    override public func collapseAtStart(selection: RangeSelection) throws -> Bool {
        let paragraph = createParagraphNode()

        try getChildren().forEach { node in
            try paragraph.append([node])
        }

        try replace(replaceWith: paragraph)

        return true
    }
}

@objc public class QuoteCustomDrawingAttributes: NSObject {
    public init(barColor: UIColor, barWidth: CGFloat, rounded: Bool, barInsets: UIEdgeInsets) {
        self.barColor = barColor
        self.barWidth = barWidth
        self.rounded = rounded
        self.barInsets = barInsets
    }

    let barColor: UIColor
    let barWidth: CGFloat
    let rounded: Bool
    let barInsets: UIEdgeInsets

    override public func isEqual(_ object: Any?) -> Bool {
        let lhs = self
        guard let rhs = object as? QuoteCustomDrawingAttributes else {
            return false
        }
        return lhs.barColor == rhs.barColor &&
            lhs.barWidth == rhs.barWidth &&
            lhs.rounded == rhs.rounded &&
            lhs.barInsets == rhs.barInsets
    }
}

public extension NSAttributedString.Key {
    static let quoteCustomDrawing: NSAttributedString.Key = .init(rawValue: "quoteCustomDrawing")
}

extension QuoteNode {
    static var quoteBackgroundDrawing: CustomDrawingHandler {
        return { _, attributeValue, _, _, _, _, rect, _ in
            guard let attributeValue = attributeValue as? QuoteCustomDrawingAttributes else { return }
            guard let context = UIGraphicsGetCurrentContext() else { return }

            let barColor = attributeValue.barColor
            let borderRect = CGRect(
                x: rect.minX + attributeValue.barInsets.left,
                y: rect.minY + attributeValue.barInsets.top,
                width: attributeValue.barWidth,
                height: rect.height - attributeValue.barInsets.top - attributeValue.barInsets.bottom
            )

            context.setFillColor(barColor.cgColor)

            if attributeValue.rounded {
                let bezierPath = UIBezierPath(roundedRect: borderRect, cornerRadius: attributeValue.barWidth / 2)
                bezierPath.fill()
            } else {
                context.fill(borderRect)
            }
        }
    }
}
