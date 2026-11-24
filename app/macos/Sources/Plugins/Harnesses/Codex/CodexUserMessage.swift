import ChiefCore
import ChiefPluginUI

extension CodexMessage {
    var transcriptInput: ThreadTranscriptInput {
        .init(content, followUp: kind == "follow-up", createdAt: raw["createdAt"]?.numberValue,
            annotations: annotations.map(ThreadMessageAnnotation.init(json:)), attachments: attachments.filter { attachment in
                !annotations.contains { $0["screenshotId"] == attachment["id"] }
            }.map { attachment in
                ThreadMessageAttachment(id: attachment.codexIdentity("id"), label: attachment["name"]?.stringValue ?? "",
                    mimeType: attachment["mimeType"]?.stringValue, kind: attachment["kind"]?.stringValue)
            })
    }
}
