import Foundation
import Testing
@testable import PlainwireCore

@Test func forumMetadataHandlesSQLNullAndDecimalIDs() throws {
  let json = #"{"id":"5","slug":"design","name":"Design","description":null,"owner_id":null,"last_at":"null","thread_count":"12","reply_count":30,"member_count":"42","joined":true}"#
  let forum = try JSONDecoder().decode(PWForum.self, from: Data(json.utf8))
  #expect(forum.id == 5 && forum.joined)
  #expect(forum.description.isEmpty && forum.ownerId == nil && forum.lastAt == nil)
  #expect(forum.threadCount == 12 && forum.replyCount == 30 && forum.memberCount == 42)
}

@Test func forumPermissionsDefaultToDeniedAndRawBodyRemainsEditable() throws {
  let json = #"{"id":700,"forum_id":5,"user_id":7,"username":"alice","display_name":null,"avatar_url":null,"title":"A discussion","body":"![image](https://cdn.example/image)","raw_body":"https://example.com/image.png","created_at":10}"#
  let thread = try JSONDecoder().decode(PWForumThread.self, from: Data(json.utf8))
  #expect(!thread.canEdit && !thread.canDelete && !thread.canModerate && !thread.viewerJoined)
  #expect(thread.displayName == "alice" && thread.avatarURL.isEmpty)
  #expect(thread.rawBody == "https://example.com/image.png")
  #expect(thread.updatedAt == 10)
}

@Test func forumReplyPermissionsAndWireFieldsDecode() throws {
  let json = #"{"thread":{"id":700,"forum_id":5,"forum_name":"Design","user_id":7,"username":"alice","title":"Hello","body":"Hello","locked":true,"pinned":true,"can_moderate":true,"viewer_joined":true},"replies":[{"id":"9","thread_id":"700","user_id":"8","username":"bob","body":"Rendered body","raw_body":"Editable body","created_at":10,"updated_at":20,"can_edit":true,"can_delete":false}]}"#
  let detail = try JSONDecoder().decode(PWForumThreadDetail.self, from: Data(json.utf8))
  #expect(detail.thread.locked && detail.thread.pinned && detail.thread.canModerate && detail.thread.viewerJoined)
  #expect(detail.replies.first?.id == 9 && detail.replies.first?.threadId == 700)
  #expect(detail.replies.first?.canEdit == true && detail.replies.first?.canDelete == false)
  #expect(detail.replies.first?.rawBody == "Editable body")
}

@Test func malformedForumIdentityCannotBecomeAValidResource() {
  for id in ["1.5", #""9223372036854775808""#, "true", #""null""#] {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PWForum.self, from: Data("{\"id\":\(id),\"name\":\"Test\"}".utf8))
    }
  }
}

@Test func forumSearchLimitsPreserveEmojiAndUTF8Boundaries() {
  #expect(PWForumLimits.prefix("helloé", maximumBytes: 6) == "hello")
  #expect(PWForumLimits.prefix("🧑‍💻abc", maximumBytes: 10).isEmpty)
  #expect(PWForumLimits.prefix("🧑‍💻abc", maximumBytes: 12) == "🧑‍💻a")
  let query = PWForumLimits.prefix(String(repeating: "🎉", count: 40), maximumBytes: PWForumLimits.search)
  #expect(query.utf8.count == 80 && query.count == 20)
  // 4,000 emoji fit a 12,000-character counter but are truncated by the real server.
  #expect(String(repeating: "🎉", count: 4000).utf8.count > PWForumLimits.body)
}
