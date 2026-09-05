using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace IMail.Desktop;

public sealed record MailFolder(string Name, int Total, int Unread)
{
    public string Label => Name.Equals("INBOX", StringComparison.OrdinalIgnoreCase) ? "Inbox" : Name;
    public string CountText => Total > 0 ? Total.ToString() : string.Empty;
}

public sealed class MailMessage
{
    [JsonPropertyName("uid")] public string Uid { get; set; } = "";
    [JsonPropertyName("from")] public string From { get; set; } = "";
    [JsonPropertyName("to")] public string To { get; set; } = "";
    [JsonPropertyName("cc")] public string Cc { get; set; } = "";
    [JsonPropertyName("reply_to")] public string ReplyTo { get; set; } = "";
    [JsonPropertyName("subject")] public string Subject { get; set; } = "(No subject)";
    [JsonPropertyName("date")] public string DateRaw { get; set; } = "";
    [JsonPropertyName("body_text")] public string BodyText { get; set; } = "";
    [JsonPropertyName("snippet")] public string Snippet { get; set; } = "";
    [JsonPropertyName("seen")] public bool Seen { get; set; }
    [JsonPropertyName("flagged")] public bool Flagged { get; set; }
    [JsonPropertyName("answered")] public bool Answered { get; set; }
    [JsonPropertyName("draft")] public bool Draft { get; set; }
    [JsonPropertyName("message_id")] public string MessageId { get; set; } = "";
    [JsonPropertyName("in_reply_to")] public string InReplyTo { get; set; } = "";
    [JsonPropertyName("references")] public string References { get; set; } = "";
    [JsonPropertyName("attachments")] public List<MailAttachment> Attachments { get; set; } = [];

    public string FromAddress
    {
        get
        {
            var match = Regex.Match(From, @"<\s*([^>]+@[^>]+)\s*>");
            if (match.Success) return match.Groups[1].Value.Trim();
            var bare = Regex.Match(From, @"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}", RegexOptions.IgnoreCase);
            return bare.Success ? bare.Value : From.Trim();
        }
    }

    public string Sender
    {
        get
        {
            var address = FromAddress;
            var name = From.Replace($"<{address}>", "", StringComparison.OrdinalIgnoreCase).Trim().Trim('"', '\'');
            return string.IsNullOrWhiteSpace(name) || name.Equals(address, StringComparison.OrdinalIgnoreCase) ? address : name;
        }
    }

    public string SenderInitial => string.IsNullOrWhiteSpace(Sender) ? "?" : Sender.Trim()[0].ToString().ToUpperInvariant();
    public string Preview => string.IsNullOrWhiteSpace(Snippet) ? BodyText.Replace("\r", " ").Replace("\n", " ") : Snippet;
    public string DisplayDate => DateTimeOffset.TryParse(DateRaw, out var value) ? value.LocalDateTime.ToString("MMM d, HH:mm") : DateRaw;
    public string Star => Flagged ? "★" : "☆";
}

public sealed class MailAttachment
{
    [JsonPropertyName("index")] public int Index { get; set; }
    [JsonPropertyName("filename")] public string Filename { get; set; } = "attachment";
    [JsonPropertyName("content_type")] public string ContentType { get; set; } = "application/octet-stream";
    [JsonPropertyName("size")] public long Size { get; set; }
    public string SizeText => Size switch
    {
        >= 1024 * 1024 => $"{Size / 1024d / 1024d:0.0} MB",
        >= 1024 => $"{Size / 1024d:0.0} KB",
        _ => $"{Size} B"
    };
}

public sealed record UploadAttachment(string Filename, string ContentType, byte[] Bytes);
public sealed record Identity(string Address, string DisplayName);
public sealed record ExternalAccountSettings(string Address, string Password, string Username, string DisplayName, string ImapHost, int ImapPort, string ImapSecurity, string SmtpHost, int SmtpPort, string SmtpSecurity);
