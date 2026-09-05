using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace IMail.Desktop;

public sealed class IMailApiClient
{
    private readonly CookieContainer _cookies = new();
    private readonly HttpClient _http;
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web) { PropertyNameCaseInsensitive = true };
    private bool _external;

    public IMailApiClient(string? baseUrl = null)
    {
        var handler = new HttpClientHandler { CookieContainer = _cookies, AutomaticDecompression = DecompressionMethods.All };
        _http = new HttpClient(handler) { BaseAddress = new Uri((baseUrl ?? "https://api.ithute.co.ls/api/v1").TrimEnd('/') + "/"), Timeout = TimeSpan.FromSeconds(30) };
        _http.DefaultRequestHeaders.Accept.ParseAdd("application/json");
    }

    private string MailBase => _external ? "webmail/external" : "webmail";
    public bool IsExternalSession => _external;
    public string Address { get; private set; } = "";

    public async Task<string> LoginAsync(string address, string password, CancellationToken ct = default)
    {
        address = address.Trim().ToLowerInvariant();
        var known = await _http.PostAsJsonAsync("webmail/external/known-session", new { address, password }, _json, ct);
        if (known.IsSuccessStatusCode)
        {
            _external = true;
            Address = await ReadAddressAsync(known, address, ct);
            return Address;
        }
        if (known.StatusCode != HttpStatusCode.NotFound) await ThrowAsync(known, ct);

        var hosted = await _http.PostAsJsonAsync("webmail/session", new { address, password }, _json, ct);
        if (!hosted.IsSuccessStatusCode) await ThrowAsync(hosted, ct);
        _external = false;
        Address = await ReadAddressAsync(hosted, address, ct);
        return Address;
    }

    public async Task RegisterExternalAsync(ExternalAccountSettings s, CancellationToken ct = default)
    {
        var payload = new
        {
            address = s.Address.Trim().ToLowerInvariant(), password = s.Password,
            username = string.IsNullOrWhiteSpace(s.Username) ? s.Address.Trim().ToLowerInvariant() : s.Username.Trim(),
            display_name = s.DisplayName.Trim(), imap_host = s.ImapHost.Trim(), imap_port = s.ImapPort,
            imap_security = s.ImapSecurity, smtp_host = s.SmtpHost.Trim(), smtp_port = s.SmtpPort, smtp_security = s.SmtpSecurity
        };
        var response = await _http.PostAsJsonAsync("webmail/external/register-known", payload, _json, ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
    }

    public async Task LogoutAsync(CancellationToken ct = default)
    {
        try { await _http.DeleteAsync($"{MailBase}/session", ct); }
        catch { }
        _external = false;
        Address = "";
    }

    public async Task<List<MailFolder>> GetFoldersAsync(CancellationToken ct = default)
    {
        var foldersResponse = await _http.GetAsync($"{MailBase}/folders", ct);
        var countsResponse = await _http.GetAsync($"{MailBase}/folder-counts", ct);
        if (!foldersResponse.IsSuccessStatusCode) await ThrowAsync(foldersResponse, ct);
        if (!countsResponse.IsSuccessStatusCode) await ThrowAsync(countsResponse, ct);
        using var foldersDoc = JsonDocument.Parse(await foldersResponse.Content.ReadAsStringAsync(ct));
        using var countsDoc = JsonDocument.Parse(await countsResponse.Content.ReadAsStringAsync(ct));
        var counts = new Dictionary<string, (int total, int unread)>(StringComparer.OrdinalIgnoreCase);
        if (countsDoc.RootElement.TryGetProperty("items", out var countItems))
            foreach (var item in countItems.EnumerateArray())
            {
                var name = GetString(item, "name", "folder");
                if (string.IsNullOrWhiteSpace(name)) continue;
                counts[name] = (GetInt(item, "messages", "total", "count"), GetInt(item, "unseen", "unread"));
            }
        var result = new List<MailFolder>();
        if (foldersDoc.RootElement.TryGetProperty("items", out var items))
            foreach (var item in items.EnumerateArray())
            {
                var name = GetString(item, "name");
                if (string.IsNullOrWhiteSpace(name)) continue;
                var count = counts.TryGetValue(name, out var c) ? c : default;
                result.Add(new MailFolder(name, count.total, count.unread));
            }
        return result;
    }

    public async Task<List<MailMessage>> GetMessagesAsync(string folder, string query = "", int limit = 100, int offset = 0, CancellationToken ct = default)
    {
        var url = $"{MailBase}/messages?folder={Uri.EscapeDataString(folder)}&limit={limit}&offset={offset}&q={Uri.EscapeDataString(query)}";
        var response = await _http.GetAsync(url, ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        if (!doc.RootElement.TryGetProperty("items", out var items)) return [];
        return items.EnumerateArray().Select(x => JsonSerializer.Deserialize<MailMessage>(x.GetRawText(), _json)!).Where(x => x is not null).ToList();
    }

    public async Task<MailMessage> GetMessageAsync(string uid, string folder, CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{MailBase}/messages/{Uri.EscapeDataString(uid)}?folder={Uri.EscapeDataString(folder)}", ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
        return (await response.Content.ReadFromJsonAsync<MailMessage>(_json, ct)) ?? new MailMessage { Uid = uid };
    }

    public async Task SetFlagsAsync(string uid, string folder, bool? seen = null, bool? flagged = null, CancellationToken ct = default)
    {
        var request = new HttpRequestMessage(HttpMethod.Patch, $"{MailBase}/messages/{Uri.EscapeDataString(uid)}/flags?folder={Uri.EscapeDataString(folder)}")
        { Content = JsonContent.Create(new { seen, flagged }) };
        var response = await _http.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
    }

    public async Task MoveAsync(string uid, string folder, string destination, CancellationToken ct = default)
    {
        var response = await _http.PostAsJsonAsync($"{MailBase}/messages/{Uri.EscapeDataString(uid)}/move?folder={Uri.EscapeDataString(folder)}", new { destination }, _json, ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
    }

    public async Task DeleteAsync(string uid, string folder, CancellationToken ct = default)
    {
        var response = await _http.DeleteAsync($"{MailBase}/messages/{Uri.EscapeDataString(uid)}?folder={Uri.EscapeDataString(folder)}", ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
    }

    public async Task SendAsync(IEnumerable<string> to, IEnumerable<string> cc, IEnumerable<string> bcc, string subject, string body, IEnumerable<UploadAttachment> attachments, string inReplyTo = "", string references = "", CancellationToken ct = default)
    {
        var payload = new
        {
            to = to.ToArray(), cc = cc.ToArray(), bcc = bcc.ToArray(), subject, body_text = body,
            attachments = attachments.Select(a => new { filename = a.Filename, content_type = a.ContentType, content_b64 = Convert.ToBase64String(a.Bytes) }).ToArray(),
            in_reply_to = inReplyTo, references
        };
        var response = await _http.PostAsJsonAsync($"{MailBase}/send", payload, _json, ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
    }

    public async Task SaveDraftAsync(IEnumerable<string> to, IEnumerable<string> cc, string subject, string body, CancellationToken ct = default)
    {
        var response = await _http.PostAsJsonAsync($"{MailBase}/drafts", new { to = to.ToArray(), cc = cc.ToArray(), subject, body_text = body }, _json, ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
    }

    public async Task<byte[]> DownloadAttachmentAsync(string uid, int index, string folder, CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{MailBase}/messages/{Uri.EscapeDataString(uid)}/attachments/{index}?folder={Uri.EscapeDataString(folder)}", ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
        return await response.Content.ReadAsByteArrayAsync(ct);
    }

    public async Task<Identity> GetIdentityAsync(CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{MailBase}/identity", ct);
        if (!response.IsSuccessStatusCode) await ThrowAsync(response, ct);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        return new Identity(GetString(doc.RootElement, "address"), GetString(doc.RootElement, "display_name"));
    }

    private async Task<string> ReadAddressAsync(HttpResponseMessage response, string fallback, CancellationToken ct)
    {
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        return GetString(doc.RootElement, "address") is { Length: > 0 } value ? value : fallback;
    }

    private static string GetString(JsonElement e, params string[] names)
    {
        foreach (var n in names) if (e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String) return v.GetString() ?? "";
        return "";
    }
    private static int GetInt(JsonElement e, params string[] names)
    {
        foreach (var n in names) if (e.TryGetProperty(n, out var v) && v.TryGetInt32(out var i)) return i;
        return 0;
    }

    private static async Task ThrowAsync(HttpResponseMessage response, CancellationToken ct)
    {
        var text = await response.Content.ReadAsStringAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(text);
            if (doc.RootElement.TryGetProperty("detail", out var detail)) text = detail.ToString();
        }
        catch { }
        throw new InvalidOperationException(string.IsNullOrWhiteSpace(text) ? $"Request failed ({(int)response.StatusCode})" : text);
    }
}
