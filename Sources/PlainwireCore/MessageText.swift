import Foundation

public struct PWTextBlock: Hashable, Sendable {
  public enum Kind: Hashable, Sendable { case markdown, code(language: String) }
  public let kind: Kind
  public let text: String
}

public enum PWMessageText {
  // Redact before extracting code blocks so a fence inside a spoiler cannot
  // accidentally expose its contents in a separate code card.
  public static func redactingSpoilers(_ text: String) -> String {
    text.replacingOccurrences(of: #"(?s)\|\|.*?\|\|"#, with: "[Spoiler]", options: .regularExpression)
  }

  public static func blocks(_ text: String) -> [PWTextBlock] {
    var result: [PWTextBlock] = []
    var buffer: [String] = []
    var language: String?
    func flush() {
      guard !buffer.isEmpty else { return }
      let body = buffer.joined(separator: "\n")
      if language != nil || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(PWTextBlock(kind: language.map { .code(language: $0) } ?? .markdown, text: body))
      }
      buffer = []
    }
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        let suffix = String(trimmed.dropFirst(3))
        if language == nil {
          flush()
          language = suffix.trimmingCharacters(in: .whitespaces)
        } else if suffix.trimmingCharacters(in: .whitespaces).isEmpty {
          flush()
          language = nil
        } else {
          buffer.append(line)
        }
      } else {
        buffer.append(line)
      }
    }
    flush()
    return result
  }
  private static let attachmentRegex = try? NSRegularExpression(
    pattern: #"(!?)\[([^\]\r\n]{0,240})\]\(([^)\r\n]{1,8192})\)"#)
  private static let spoilerRegex = try? NSRegularExpression(pattern: #"(?s)\|\|.*?\|\|"#)
  private static let literalCodeRegex = try? NSRegularExpression(pattern: #"(?s)```.*?(?:```|$)|`[^`\r\n]*`"#)
  private static let embeddedImageDataRegex = try? NSRegularExpression(
    pattern: #"data:image/[A-Za-z0-9.+-]+;base64,[A-Za-z0-9+/=\r\n]{128,}"#,
    options: [.caseInsensitive])

  public static func parseBody(_ body: String) -> (
    text: String, attachments: [PWAttachment]
  ) {
    var working = body
    var attachments: [PWAttachment] = []

    if let regex = attachmentRegex {
      let bodyRange = NSRange(body.startIndex..., in: body)
      let spoilerRanges = spoilerRegex?.matches(in: body, range: bodyRange).map(\.range) ?? []
      let codeRanges = literalCodeRegex?.matches(in: body, range: bodyRange).map(\.range) ?? []
      let matches = regex.matches(in: body, range: bodyRange)
      for match in matches.reversed() {
        guard !codeRanges.contains(where: { NSLocationInRange(match.range.location, $0) }) else { continue }
        guard let whole = Range(match.range(at: 0), in: working),
          let imageFlag = Range(match.range(at: 1), in: working),
          let nameRange = Range(match.range(at: 2), in: working),
          let urlRange = Range(match.range(at: 3), in: working)
        else { continue }

        let name = String(working[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let url = String(working[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let isImage = !String(working[imageFlag]).isEmpty
        let isVoice = url.contains("#plainwire-voice-note")
        let isPlainwireFile = url.contains("/api/files/") || url.contains("/api/media/")
        guard isImage || isVoice || isPlainwireFile else { continue }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v"].contains(fileExtension)
          || ["mp4", "mov", "m4v"].contains(
            ((URLComponents(string: url)?.path ?? "") as NSString).pathExtension.lowercased())
        let kind: PWAttachment.Kind = isVoice ? .voice : (isImage ? .image : (isVideo ? .video : .file))
        let hasSpoilerPrefix = working[..<whole.lowerBound].hasSuffix("||")
        let hasSpoilerSuffix = working[whole.upperBound...].hasPrefix("||")
        let isolatedSpoiler = hasSpoilerPrefix && hasSpoilerSuffix
        let isSpoiler = isolatedSpoiler || spoilerRanges.contains(where: { NSLocationInRange(match.range.location, $0) })
        attachments.insert(
          PWAttachment(
            name: name.isEmpty ? (isImage ? "Image" : (isVideo ? "Video" : "Attachment")) : name,
            url: url, kind: kind, isSpoiler: isSpoiler),
          at: 0)
        if isolatedSpoiler {
          let start = working.index(whole.lowerBound, offsetBy: -2)
          let end = working.index(whole.upperBound, offsetBy: 2)
          working.removeSubrange(start..<end)
        } else {
          working.removeSubrange(whole)
        }
      }
    }

    if let dataRegex = embeddedImageDataRegex {
      working = dataRegex.stringByReplacingMatches(
        in: working, range: NSRange(working.startIndex..., in: working),
        withTemplate: "[Image attachment]")
    }

    let text =
      working
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (text, attachments)
  }


}


public struct PWAttachment: Hashable, Identifiable, Sendable {
  public enum Kind: Hashable, Sendable { case image, video, file, voice }
  public let name: String
  public let url: String
  public let kind: Kind
  public let isSpoiler: Bool
  public var id: String { "\(kind):\(url):\(name):\(isSpoiler)" }
}
