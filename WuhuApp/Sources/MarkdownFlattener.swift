import Foundation
import Markdown
import WuhuDocView

// MARK: - Public API

/// Converts a raw markdown string into a flat array of `FlatBlock`s suitable
/// for rendering with `WuhuDocView`.
///
/// This is the bridge between Apple's `swift-markdown` AST and the flat IR
/// that `DocView` consumes. It lives in the app (not in `WuhuDocView`) because
/// the rendering engine is intentionally parser-agnostic.
enum MarkdownFlattener {

  /// Parse a markdown string and flatten it into blocks within the given section.
  static func flatten(_ markdown: String, sectionID: String) -> [FlatBlock] {
    let document = Markdown.Document(parsing: markdown)
    var walker = BlockFlattener(sectionID: sectionID)
    walker.visit(document)
    return walker.blocks
  }

  /// Build a complete `Document` for a workspace doc, including a custom
  /// header block with title, tags, and updated-at metadata.
  static func buildDocDocument(
    id: String,
    title: String,
    tags: [String],
    updatedAt: Date,
    markdownContent: String
  ) -> WuhuDocView.Document {
    var headerFields: [String: String] = ["title": title]
    if !tags.isEmpty {
      headerFields["tags"] = tags.joined(separator: ",")
    }
    headerFields["updatedAt"] = updatedAt.formatted(.relative(presentation: .named))

    let headerBlock = FlatBlock(
      id: BlockID(sectionID: id, index: 0, kind: .custom("docHeader")),
      content: .custom(CustomBlockContent(headerFields))
    )

    let contentBlocks = flatten(markdownContent, sectionID: id)

    var allBlocks = [headerBlock]
    for (i, var block) in contentBlocks.enumerated() {
      block.id = BlockID(
        sectionID: id,
        index: i + 1,
        kind: block.kind
      )
      allBlocks.append(block)
    }

    let section = DocSection(id: id, blocks: allBlocks)
    return WuhuDocView.Document(sections: [section])
  }

  /// Build a simple `Document` from raw markdown content without a header.
  /// Used by the new docs tree view where the breadcrumb replaces the header.
  static func buildSimpleDocument(
    id: String,
    markdownContent: String
  ) -> WuhuDocView.Document {
    let contentBlocks = flatten(markdownContent, sectionID: id)

    var allBlocks: [FlatBlock] = []
    for (i, var block) in contentBlocks.enumerated() {
      block.id = BlockID(
        sectionID: id,
        index: i,
        kind: block.kind
      )
      allBlocks.append(block)
    }

    let section = DocSection(id: id, blocks: allBlocks)
    return WuhuDocView.Document(sections: [section])
  }
}

// MARK: - Block Flattener (MarkupWalker)

/// Walks the `swift-markdown` AST depth-first and emits `FlatBlock`s.
///
/// Container nodes (blockquotes, lists) modify the indent/decoration context
/// for their children. Leaf block nodes (paragraph, heading, code block, etc.)
/// emit one `FlatBlock` each.
private struct BlockFlattener: MarkupWalker {

  let sectionID: String
  private(set) var blocks: [FlatBlock] = []

  /// Current nesting depth — incremented by lists and blockquotes.
  private var indent: Int = 0

  /// Whether we're currently inside a blockquote context.
  private var inBlockquote: Bool = false

  /// When set, the next paragraph emitted gets this decoration.
  private var pendingDecoration: Decoration?

  init(sectionID: String) {
    self.sectionID = sectionID
  }

  // MARK: - Block-Level Visitors

  mutating func visitHeading(_ heading: Heading) {
    let level = heading.level
    let content = renderInlines(heading.inlineChildren)
    emit(kind: .heading(level: level), content: .text(content))
  }

  mutating func visitParagraph(_ paragraph: Paragraph) {
    let content = renderInlines(paragraph.inlineChildren)
    let decoration = pendingDecoration
    pendingDecoration = nil
    emit(
      kind: .paragraph,
      content: .text(content),
      indent: indent,
      decoration: decoration
    )
  }

  mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
    let language = codeBlock.language
    let code = codeBlock.code
    emit(
      kind: .codeBlock,
      content: .codeBlock(CodeBlockContent(language: language, code: code)),
      indent: indent
    )
  }

  mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
    emit(kind: .thematicBreak, content: .thematicBreak)
  }

  mutating func visitTable(_ table: Table) {
    let headers = Array(table.head.cells.map { cell in
      cell.plainText
    })
    let rows = Array(table.body.rows.map { row in
      Array(row.cells.map { cell in
        cell.plainText
      })
    })
    emit(
      kind: .table,
      content: .table(TableContent(headers: headers, rows: rows)),
      indent: indent
    )
  }

  mutating func visitImage(_ image: Markdown.Image) {
    if let source = image.source {
      let altText = image.plainText
      emit(
        kind: .image,
        content: .image(ImageContent(url: source, altText: altText.isEmpty ? nil : altText)),
        indent: indent
      )
    }
  }

  // MARK: - Container Visitors

  mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
    let wasInBlockquote = inBlockquote
    inBlockquote = true
    indent += 1
    for child in blockQuote.children {
      visit(child)
    }
    indent -= 1
    inBlockquote = wasInBlockquote
  }

  mutating func visitOrderedList(_ orderedList: OrderedList) {
    for (i, item) in orderedList.listItems.enumerated() {
      let number = Int(orderedList.startIndex) + i
      visitListItem(item, decoration: inBlockquote ? .quoteBarAndOrdered(number) : .ordered(number))
    }
  }

  mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
    for item in unorderedList.listItems {
      visitListItem(item, decoration: inBlockquote ? .quoteBarAndBullet : .bullet)
    }
  }

  private mutating func visitListItem(_ item: ListItem, decoration: Decoration) {
    indent += 1
    pendingDecoration = decoration
    for child in item.children {
      visit(child)
    }
    // Clear any unused pending decoration (e.g. empty list item)
    pendingDecoration = nil
    indent -= 1
  }

  // MARK: - Helpers

  private mutating func emit(
    kind: BlockKind,
    content: BlockContent,
    indent: Int = 0,
    decoration: Decoration? = nil
  ) {
    let index = blocks.count
    let block = FlatBlock(
      id: BlockID(sectionID: sectionID, index: index, kind: kind),
      content: content,
      indent: indent,
      decoration: decoration
    )
    blocks.append(block)
  }

  // MARK: - Inline Rendering

  /// Converts inline markup children into an `InlineContent` with styled
  /// `AttributedString`.
  private func renderInlines(_ inlines: some Sequence<InlineMarkup>) -> InlineContent {
    var result = AttributedString()
    for inline in inlines {
      result.append(renderInline(inline))
    }
    return InlineContent(result)
  }

  private func renderInline(_ inline: InlineMarkup) -> AttributedString {
    switch inline {
    case let text as Markdown.Text:
      return AttributedString(text.string)

    case let strong as Strong:
      var s = AttributedString()
      for child in strong.inlineChildren {
        s.append(renderInline(child))
      }
      s.inlinePresentationIntent = .stronglyEmphasized
      return s

    case let emphasis as Emphasis:
      var s = AttributedString()
      for child in emphasis.inlineChildren {
        s.append(renderInline(child))
      }
      s.inlinePresentationIntent = .emphasized
      return s

    case let code as InlineCode:
      var s = AttributedString(code.code)
      s.inlinePresentationIntent = .code
      return s

    case let link as Markdown.Link:
      var s = AttributedString()
      for child in link.inlineChildren {
        s.append(renderInline(child))
      }
      if let dest = link.destination, let url = URL(string: dest) {
        s.link = url
      }
      return s

    case is SoftBreak:
      return AttributedString(" ")

    case is LineBreak:
      return AttributedString("\n")

    case let strikethrough as Strikethrough:
      var s = AttributedString()
      for child in strikethrough.inlineChildren {
        s.append(renderInline(child))
      }
      s.inlinePresentationIntent = .strikethrough
      return s

    case let inlineHTML as InlineHTML:
      return AttributedString(inlineHTML.rawHTML)

    default:
      // Fallback: extract plain text
      return AttributedString(inline.plainText)
    }
  }
}

// MARK: - Markup Helpers

private extension Markup {
  var inlineChildren: [InlineMarkup] {
    children.compactMap { $0 as? InlineMarkup }
  }
}
