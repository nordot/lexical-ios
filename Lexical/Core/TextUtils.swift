/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

internal func isRootTextContentEmpty(isEditorComposing: Bool, trim: Bool = true) -> Bool {
  if isEditorComposing {
    return false
  }

  var text = rootTextContent()
  if trim {
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  return text.isEmpty
}

internal func isTitleTextContentEmpty(isEditorComposing: Bool, trim: Bool = true) -> Bool {
  if isEditorComposing {
    return false
  }

  var text = titleTextContent()
  if trim {
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  return text.isEmpty
}

internal func isBodyTextContentEmpty(isEditorComposing: Bool, trim: Bool = true) -> Bool {
  if isEditorComposing {
    return false
  }

  var text = bodyTextContent()
  if trim {
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  return text.isEmpty
}

internal func rootTextContent() -> String {
  guard let root = getRoot() else { return "" }

  return root.getTextContent()
}

internal func titleTextContent() -> String {
  guard let root = getRoot() else { return "" }

  return root.getTitleTextContent()
}

internal func bodyTextContent() -> String {
  guard let root = getRoot() else { return "" }

  return root.getBodyTextContent()
}

internal func canShowTitlePlaceholder(isComposing: Bool) -> Bool {
  return isTitleTextContentEmpty(isEditorComposing: isComposing)
}


internal func canShowBodyPlaceholder(isComposing: Bool) -> Bool {
  if !isBodyTextContentEmpty(isEditorComposing: isComposing) {
    return false
  }

  guard let root = getRoot() else { return false }

  let children = root.getBodyChildren()
  if children.count > 1 {
    return false
  }

  for childNode in children {
    guard let childNode = childNode as? ElementNode else { return true }

    if childNode.type != NodeType.paragraph {
      return false
    }

    let nodeChildren = childNode.getChildren()
    for nodeChild in nodeChildren {
      if !isTextNode(nodeChild) {
        return false
      }
    }
  }

  return true
}
