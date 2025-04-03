/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

public class ParagraphNode: ElementNode {
  override public init() {
    super.init()
  }

  override required init(_ key: NodeKey?) {
    super.init(key)
  }

  public required init(from decoder: Decoder) throws {
    try super.init(from: decoder)
  }

  override public class func getType() -> NodeType {
    return .paragraph
  }

  override public func encode(to encoder: Encoder) throws {
    try super.encode(to: encoder)
  }

  override public func clone() -> Self {
    Self(key)
  }

  override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
    let isShowTitlePlaceHolder = getFlagShowTitlePlaceHolder() ?? false
    if isShowTitlePlaceHolder {
      let titleNode = getRoot()?.getTitleNode()
      if titleNode == self {
        if let title = theme.title {
          return title
        }
      }
    }

    if let paragraph = theme.paragraph {
      return paragraph
    }

    return [:]
  }

  override open func insertNewAfter(selection: RangeSelection?) throws -> ParagraphNode? {
    let newElement = createParagraphNode()
    let direction = getDirection()
    do {
      if let selection = try getSelection() as? RangeSelection {
          let selectedNodes = try selection.getNodes()
          let anchor = selection.anchor
          let focus = selection.focus
          let isBackward = try selection.isBackward()
          let endOffset = isBackward ? focus.offset : anchor.offset
          let firstNode = selectedNodes.first
          let lastNode = selectedNodes.last
          let topElementFirstNode = firstNode?.getTopLevelElement()
          let topElementLastNode = lastNode?.getTopLevelElement()
          let textContentSize = topElementFirstNode?.getTextContent().replacingOccurrences(of: "\n", with: "")

          if topElementFirstNode == topElementLastNode && endOffset == textContentSize?.count {
             selection.clearFormat()
          }
      }

      try newElement.setDirection(direction: direction)
      try insertAfter(nodeToInsert: newElement)
    } catch {
      throw LexicalError.internal("Error in insertNewAfter: \(error.localizedDescription)")
    }
    return newElement
  }

  public func createParagraphNode() -> ParagraphNode {
    return ParagraphNode()
  }
}
