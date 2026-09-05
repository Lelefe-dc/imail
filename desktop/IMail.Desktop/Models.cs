using System.Text.Json.Serialization;

namespace IMail.Desktop;

public sealed record MailFolder(string Name, int Total, int Unread)
{
    public string Label => Name.Equals("INBOX", StringComparison.OrdinalIgnoreCase) ? "Inbox" : Name;
    public string CountText => Total > 0 ? Total.ToString() : string.Empty;
}

public sealed class MailMessage
{
    [JsonPropertyName("uid")] public string Uid { get; set; } = "";
    [JsonPropertyName("subject")] public string Subject { get; set; } = "(No subject)";
    [JsonPropertyName("from_name")] public string FromName { get; set; } = "";
    [JsonPropertyName("from_address")] public string FromAddress { get; set; } = "";
    [JsonPropertyName("to")] public List<string> To { get; set; } = [];
    [JsonPropertyName("cc")] public List<string> Cc { get; set; } = [];
    [JsonPropertyName("bcc")] public List<string> Bcc { get; set; } = [];
    [JsonPropertyName("date")] public string DateRaw { get; set; } = "";
    [JsonPropertyName("body_text")] public string BodyText { get; set; } = "";
    [JsonPropertyName("snippet")] public string Snippet { get; set; } = "";
    [JsonPropertyName("seen")] public bool Seen { get; set; }
    [JsonPropertyName("flagged")] public bool Flagged { get; set; }
    [JsonPropertyName("message_id")] public string MessageId { get; set; } = "";
    [JsonPropertyName("in_reply_to")] public string InReplyTo { get; set; } = "";
    [JsonPropertyName("references")] public string References { get; set; } = "";
    [JsonPropertyName("attachments")] public List<MailAttachment> Attachments { get; set; } = [];

    public string Sender => string.IsNullOrWhiteSpace(FromName) ? FromAddress : FromName;
    public string SenderInitial => string.IsNullOrWhiteSpace(Sender) ? "?" : Sender.Trim()[0].ToString().ToUpperInvariant();
    public string Preview => string.IsNullOrWhiteSpace(Snippet) ? BodyText.Replace("\r", " ").Replace("\n", " ") : Snippet;
    public string DisplayDate => DateTimeOffset.TryParse(DateRaw, out var value) ? value.LocalDateTime.ToString("MMM d, HH:mm") : DateRaw;
    public string Star => Flagged ? "★" : "☆";
}

public sealed class MailAttachment
{
    [JsonPropertyName("filename")] public string Filename { get; set; } = "attachment";
    [JsonPropertyName("content_type")] public string ContentType { get; set; } = "application/octet-stream";
    [JsonPropertyName("size")] public long Size { get; set; }
}

public sealed record UploadAttachment(string Filename, string ContentType, byte[] Bytes);
public sealed record Identity(string Address, string DisplayName);
public sealed record ExternalAccountSettings(string Address, string Password, string Username, string DisplayName, string ImapHost, int ImapPort, string ImapSecurity, string SmtpHost, int SmtpPort, string SmtpSecurity);
