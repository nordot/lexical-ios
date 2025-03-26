/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

public class RootNode: ElementNode {

  override required init() {
    super.init(kRootNodeKey)
  }

  public required init(from decoder: Decoder) throws {
    try super.init(from: decoder)
  }

  override public func encode(to encoder: Encoder) throws {
    try super.encode(to: encoder)
  }

  override public func clone() -> Self {
    Self()
  }

  override public static func getType() -> NodeType {
    return .root
  }

  override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
    if let root = theme.root {
      return root
    }

    return [.font: LexicalConstants.defaultFont]
  }

  // Root nodes cannot have a preamble. If they did, there would be no way to make a selection of the
  // beginning of the document. The same applies to postamble.
  override public final func getPreamble() -> String {
    return ""
  }

  override public func getTextContent(includeInert: Bool = false, includeDirectionless: Bool = false) -> String {
    return super.getTextContent(includeInert: includeInert, includeDirectionless: includeDirectionless)
  }

  public func getTitleNode<T: Node>() -> T? {
    let isShowTitlePlaceHolder = getFlagShowTitlePlaceHolder() ?? false
    if !isShowTitlePlaceHolder {
      return nil
    }
    let children = getLatest().children

    if children.count == 0 {
      return nil
    }

    guard let firstChild = children.first else { return nil }

    return getNodeByKey(key: firstChild)
  }

  public func getLastHiddenNode<T: Node>() -> T? {
    let children = getLatest().children

    if children.count == 0 {
      return nil
    }

    guard let lastChild = children.last else { return nil }

    return getNodeByKey(key: lastChild)
  }

  public func getTitleTextContent(includeInert: Bool = false, includeDirectionless: Bool = false) -> String {
      if let titleNode = getTitleNode() {
          return titleNode.getTextContent(includeInert: includeInert, includeDirectionless: includeDirectionless)
      } else {
          return ""
      }
  }

  public func getBodyTextContent(includeInert: Bool = false, includeDirectionless: Bool = false) -> String {
    let children = getChildren()
    let preamble = getPreamble()
    let postamble = getPostamble()
    let titleNode = getTitleNode()
    let hiddenNode = getLastHiddenNode()

    var textContent = ""

    textContent += preamble

    for child in children {
      if titleNode == child || hiddenNode == child {
          continue
      }

      textContent += child.getTextContent(includeInert: includeInert, includeDirectionless: includeDirectionless)
      if child is LineBreakNode {
        textContent += child.getPostamble()
      }
    }

    textContent += postamble

    return textContent
  }

  public func getBodyChildren() -> [Node] {
    let titleNode = getTitleNode()
    let hiddenNode = getLastHiddenNode()

    return getLatest().children.compactMap { nodeKey in
        let node = getNodeByKey(key: nodeKey)
        return node == titleNode || node == hiddenNode ? nil : node
    }
  }

  override public final func getPostamble() -> String {
    return ""
  }

  override public func insertBefore(nodeToInsert: Node) throws -> Node {
    throw LexicalError.invariantViolation("insertBefore: cannot be called on root nodes")
  }

  override public func remove() throws {
    throw LexicalError.invariantViolation("remove: cannot be called on root nodes")
  }

  override public func replace<T: Node>(replaceWith: T, includeChildren: Bool = false) throws -> T {
    throw LexicalError.invariantViolation("replace: cannot be called on root nodes")
  }

  override public func insertAfter(nodeToInsert: Node) throws -> Node {
    throw LexicalError.invariantViolation("insertAfter: cannot be called on root nodes")
  }
}

extension RootNode: CustomDebugStringConvertible {
  public var debugDescription: String {
    return "(RootNode: key '\(key)', id \(ObjectIdentifier(self))"
  }
}
