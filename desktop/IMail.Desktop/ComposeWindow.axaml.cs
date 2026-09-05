using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;

namespace IMail.Desktop;

public partial class ComposeWindow : Window
{
    private readonly IMailApiClient _api;
    private readonly List<UploadAttachment> _attachments = [];
    private readonly string _inReplyTo;
    private readonly string _references;

    public ComposeWindow(IMailApiClient api, string to = "", string subject = "", string body = "", string inReplyTo = "", string references = "")
    {
        InitializeComponent();
        _api = api;
        _inReplyTo = inReplyTo;
        _references = references;
        ToBox.Text = to;
        SubjectBox.Text = subject;
        BodyBox.Text = body;
    }

    private async void Attach_Click(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Attach files",
            AllowMultiple = true
        });
        foreach (var file in files)
        {
            await using var stream = await file.OpenReadAsync();
            using var ms = new MemoryStream();
            await stream.CopyToAsync(ms);
            if (ms.Length > 25 * 1024 * 1024)
            {
                StatusText.Text = $"{file.Name} is larger than 25 MB.";
                continue;
            }
            _attachments.Add(new UploadAttachment(file.Name, GuessContentType(file.Name), ms.ToArray()));
        }
        AttachmentText.Text = _attachments.Count == 0 ? "" : $"{_attachments.Count} attachment{(_attachments.Count == 1 ? "" : "s")}";
    }

    private async void Send_Click(object? sender, RoutedEventArgs e)
    {
        var to = SplitAddresses(ToBox.Text);
        if (to.Count == 0) { StatusText.Text = "Add at least one recipient."; return; }
        Progress.IsVisible = true; StatusText.Text = "";
        try
        {
            await _api.SendAsync(to, SplitAddresses(CcBox.Text), SplitAddresses(BccBox.Text), SubjectBox.Text ?? "", BodyBox.Text ?? "", _attachments, _inReplyTo, _references);
            Close(true);
        }
        catch (Exception ex) { StatusText.Text = ex.Message; }
        finally { Progress.IsVisible = false; }
    }

    private async void Draft_Click(object? sender, RoutedEventArgs e)
    {
        Progress.IsVisible = true; StatusText.Text = "";
        try
        {
            await _api.SaveDraftAsync(SplitAddresses(ToBox.Text), SplitAddresses(CcBox.Text), SubjectBox.Text ?? "", BodyBox.Text ?? "");
            Close(true);
        }
        catch (Exception ex) { StatusText.Text = ex.Message; }
        finally { Progress.IsVisible = false; }
    }

    private static List<string> SplitAddresses(string? text) => (text ?? "")
        .Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Where(x => x.Contains('@')).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

    private static string GuessContentType(string name) => Path.GetExtension(name).ToLowerInvariant() switch
    {
        ".pdf" => "application/pdf", ".png" => "image/png", ".jpg" or ".jpeg" => "image/jpeg",
        ".gif" => "image/gif", ".txt" => "text/plain", ".html" or ".htm" => "text/html",
        ".doc" => "application/msword", ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xls" => "application/vnd.ms-excel", ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".zip" => "application/zip", _ => "application/octet-stream"
    };
}
