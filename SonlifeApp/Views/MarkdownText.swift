import SwiftUI

/// LLM 이 생성한 마크다운 텍스트를 SwiftUI 로 렌더링.
///
/// LLM output 에는 # / ## / ### 헤딩, **bold**, *italic*, --- 구분선 같은
/// 마크다운이 섞여 나온다. SwiftUI 의 기본 `Text(someString)` 은 이를
/// 파싱하지 않고 문자 그대로 표시해서 `###` `**` 가 화면에 노출됐다.
///
/// 이 View 는:
/// - `# ~ ####` 헤딩을 headline / title3 폰트로
/// - `---`, `***`, `___` 를 Divider 로
/// - 나머지 문단은 `AttributedString(markdown:)` 로 inline 파싱 (bold/italic/link)
/// - 리스트 (`- `, `* `, `1. `) 는 bullet + 본문
/// 하지 않는 것: code block, blockquote, table (필요 시 추후 확장)
struct MarkdownText: View {
    let source: String

    private var blocks: [MarkdownBlock] { parseMarkdown(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(attributed(content))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let content):
            Text(attributed(content))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let content):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(attributed(content))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .rule:
            Divider()
                .padding(.vertical, 2)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    /// AttributedString 로 inline 마크다운 (**bold**, *italic*, [links]) 파싱.
    /// 실패 시 plain 으로 폴백.
    private func attributed(_ s: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let a = try? AttributedString(markdown: s, options: options) {
            return a
        }
        return AttributedString(s)
    }
}

// MARK: - Parser

enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    case rule
}

private func parseMarkdown(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paraBuffer: [String] = []

    func flushParagraph() {
        guard !paraBuffer.isEmpty else { return }
        blocks.append(.paragraph(paraBuffer.joined(separator: "\n")))
        paraBuffer.removeAll()
    }

    let lines = text.components(separatedBy: .newlines)
    for rawLine in lines {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        if line.isEmpty {
            flushParagraph()
            continue
        }

        // Horizontal rule
        if line == "---" || line == "***" || line == "___" {
            flushParagraph()
            blocks.append(.rule)
            continue
        }

        // Heading: # ~ ####
        if line.hasPrefix("#") {
            var level = 0
            for ch in line {
                if ch == "#" { level += 1 } else { break }
            }
            if level >= 1 && level <= 6 {
                let content = String(line.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    flushParagraph()
                    blocks.append(.heading(min(level, 4), content))
                    continue
                }
            }
        }

        // Bullet list: "- " or "* " or "1. "
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            flushParagraph()
            let content = String(line.dropFirst(2))
            blocks.append(.bullet(content))
            continue
        }
        if line.count >= 3, line.first?.isNumber == true {
            // crude "1. text" detection
            if let dotRange = line.range(of: ". ") {
                let prefix = line[..<dotRange.lowerBound]
                if prefix.allSatisfy({ $0.isNumber }) {
                    flushParagraph()
                    let content = String(line[dotRange.upperBound...])
                    blocks.append(.bullet(content))
                    continue
                }
            }
        }

        paraBuffer.append(line)
    }
    flushParagraph()
    return blocks
}

// MARK: - Strip helper (짧은 프리뷰용)

/// 마크다운 기호 제거 후 한 줄 요약에 적합한 plain text 반환.
///
/// 리스트/카드 row 처럼 lineLimit 1~2 로 자르는 컨텍스트에서 사용.
/// MarkdownText 처럼 블록 구조로 렌더링할 공간이 없을 때.
func stripMarkdown(_ s: String) -> String {
    var out = s

    // 헤딩 마커 제거 (# ~ ###### at line start)
    out = out.replacingOccurrences(
        of: "(^|\\n)#{1,6}\\s+",
        with: "$1",
        options: .regularExpression
    )

    // 구분선 제거
    out = out.replacingOccurrences(
        of: "(^|\\n)(---+|\\*\\*\\*+|___+)(\\n|$)",
        with: "$1",
        options: .regularExpression
    )

    // 리스트 마커 제거
    out = out.replacingOccurrences(
        of: "(^|\\n)[-*]\\s+",
        with: "$1",
        options: .regularExpression
    )
    out = out.replacingOccurrences(
        of: "(^|\\n)\\d+\\.\\s+",
        with: "$1",
        options: .regularExpression
    )

    // Bold/italic 마커 제거 (내용 유지)
    out = out.replacingOccurrences(
        of: "\\*\\*(.+?)\\*\\*",
        with: "$1",
        options: .regularExpression
    )
    out = out.replacingOccurrences(
        of: "(?<!\\*)\\*(?!\\*)(.+?)\\*(?!\\*)",
        with: "$1",
        options: .regularExpression
    )
    out = out.replacingOccurrences(
        of: "__(.+?)__",
        with: "$1",
        options: .regularExpression
    )

    // 인라인 코드
    out = out.replacingOccurrences(
        of: "`([^`]+)`",
        with: "$1",
        options: .regularExpression
    )

    // 연속 줄바꿈 → 한 칸 공백
    out = out.replacingOccurrences(
        of: "\\n+",
        with: " ",
        options: .regularExpression
    )

    // 연속 공백 → 한 칸
    out = out.replacingOccurrences(
        of: "\\s{2,}",
        with: " ",
        options: .regularExpression
    )

    return out.trimmingCharacters(in: .whitespaces)
}
