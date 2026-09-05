using System.Collections.ObjectModel;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace IMail.Desktop;

public partial class MainWindow : Window
{
    private readonly IMailApiClient _api = new();
    private readonly ObservableCollection<MailMessage> _messages = [];
    private string _folder = "INBOX";
    private MailMessage? _selected;
    private CancellationTokenSource? _searchCts;
    private CancellationTokenSource? _realtimeCts;

    public MainWindow()
    {
        InitializeComponent();
        MessageList.ItemsSource = _messages;
        SizeChanged += (_, _) => ApplyResponsiveLayout();
        Opened += (_, _) => ApplyResponsiveLayout();
        Closed += (_, _) => { _searchCts?.Cancel(); _realtimeCts?.Cancel(); };
    }

    private async void Login_Click(object? sender, RoutedEventArgs e)
    {
        LoginError.IsVisible = false;
        var email = EmailBox.Text?.Trim() ?? "";
        var password = PasswordBox.Text ?? "";
        if (email.Length == 0 || password.Length == 0) { ShowLoginError("Enter your email address and mailbox password."); return; }
        LoginProgress.IsVisible = true;
        try
        {
            var address = await _api.LoginAsync(email, password);
            PasswordBox.Text = "";
            await EnterMailboxAsync(address);
        }
        catch (Exception ex) { ShowLoginError(ex.Message); }
        finally { LoginProgress.IsVisible = false; }
    }

    private async Task EnterMailboxAsync(string address)
    {
        AccountAddressText.Text = address;
        AccountButton.Content = address.Length > 0 ? address[0].ToString().ToUpperInvariant() : "A";
        LoginView.IsVisible = false;
        MailView.IsVisible = true;
        await LoadFoldersAsync();
        await LoadMessagesAsync();
        StartRealtime();
    }

    private void StartRealtime()
    {
        _realtimeCts?.Cancel();
        _realtimeCts = new CancellationTokenSource();
        _ = RealtimeLoopAsync(_realtimeCts.Token);
    }

    private async Task RealtimeLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && !string.IsNullOrWhiteSpace(_api.Address))
        {
            try
            {
                await foreach (var _ in _api.RealtimeEventsAsync(ct))
                {
                    await Dispatcher.UIThread.InvokeAsync(async () =>
                    {
                        await LoadFoldersAsync();
                        await LoadMessagesAsync();
                    });
                }
            }
            catch (OperationCanceledException) { break; }
            catch
            {
                try { await Task.Delay(TimeSpan.FromSeconds(5), ct); } catch (OperationCanceledException) { break; }
            }
        }
    }

    private async Task LoadFoldersAsync()
    {
        try
        {
            var folders = await _api.GetFoldersAsync();
            FolderPanel.Children.Clear();
            foreach (var folder in folders)
            {
                var button = new Button { Classes = { "nav" }, Tag = folder.Name };
                var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
                grid.Children.Add(new TextBlock { Text = FolderLabel(folder.Name), FontWeight = folder.Name.Equals(_folder, StringComparison.OrdinalIgnoreCase) ? FontWeight.SemiBold : FontWeight.Normal });
                var count = new TextBlock { Text = folder.CountText, Foreground = Brushes.Gray };
                Grid.SetColumn(count, 1); grid.Children.Add(count); button.Content = grid;
                button.Click += Folder_Click;
                FolderPanel.Children.Add(button);
            }
        }
        catch (Exception ex) { await ShowInfoAsync("Folder error", ex.Message); }
    }

    private async void Folder_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string folder }) return;
        _folder = folder;
        FolderTitle.Text = FolderLabel(folder);
        ReaderView.IsVisible = false; ReaderEmpty.IsVisible = true; _selected = null;
        await LoadMessagesAsync();
        await LoadFoldersAsync();
    }

    private async Task LoadMessagesAsync(string? query = null)
    {
        MailProgress.IsVisible = true;
        try
        {
            var items = await _api.GetMessagesAsync(_folder, query ?? SearchBox.Text?.Trim() ?? "", 100, 0);
            _messages.Clear();
            foreach (var item in items) _messages.Add(item);
            FolderSubtitle.Text = items.Count == 1 ? "1 message" : $"{items.Count} messages";
        }
        catch (Exception ex) { await ShowInfoAsync("Mailbox error", ex.Message); }
        finally { MailProgress.IsVisible = false; }
    }

    private async void MessageList_SelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (MessageList.SelectedItem is not MailMessage summary) return;
        _selected = summary;
        ReaderEmpty.IsVisible = false; ReaderView.IsVisible = true;
        ReaderSubject.Text = summary.Subject; ReaderSender.Text = summary.Sender; ReaderInitial.Text = summary.SenderInitial; ReaderDate.Text = summary.DisplayDate;
        ReaderRecipients.Text = summary.FromAddress; ReaderBody.Text = "Loading message…";
        try
        {
            var full = await _api.GetMessageAsync(summary.Uid, _folder);
            _selected = full;
            ReaderSubject.Text = full.Subject; ReaderSender.Text = full.Sender; ReaderInitial.Text = full.SenderInitial; ReaderDate.Text = full.DisplayDate;
            ReaderRecipients.Text = $"from {full.FromAddress}" + (full.To.Count > 0 ? $"   to {string.Join(", ", full.To)}" : "");
            ReaderBody.Text = string.IsNullOrWhiteSpace(full.BodyText) ? "(This message has no plain-text body.)" : full.BodyText;
            if (!full.Seen) { await _api.SetFlagsAsync(full.Uid, _folder, seen: true); summary.Seen = true; await LoadFoldersAsync(); }
        }
        catch (Exception ex) { ReaderBody.Text = $"Could not load this message.\n\n{ex.Message}"; }
    }

    private async void SearchBox_KeyUp(object? sender, KeyEventArgs e)
    {
        _searchCts?.Cancel(); _searchCts = new CancellationTokenSource(); var token = _searchCts.Token;
        try { await Task.Delay(350, token); if (!token.IsCancellationRequested) await LoadMessagesAsync(SearchBox.Text?.Trim()); } catch (OperationCanceledException) { }
    }

    private async void Refresh_Click(object? sender, RoutedEventArgs e) { await LoadFoldersAsync(); await LoadMessagesAsync(); }
    private async void Compose_Click(object? sender, RoutedEventArgs e) { var compose = new ComposeWindow(_api); await compose.ShowDialog(this); await LoadFoldersAsync(); await LoadMessagesAsync(); }

    private async void Reply_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        var subject = _selected.Subject.StartsWith("Re:", StringComparison.OrdinalIgnoreCase) ? _selected.Subject : $"Re: {_selected.Subject}";
        var compose = new ComposeWindow(_api, _selected.FromAddress, subject, "", _selected.MessageId, _selected.References);
        await compose.ShowDialog(this);
    }

    private async void Forward_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        var subject = _selected.Subject.StartsWith("Fwd:", StringComparison.OrdinalIgnoreCase) ? _selected.Subject : $"Fwd: {_selected.Subject}";
        var body = $"\n\n---------- Forwarded message ----------\nFrom: {_selected.FromAddress}\nSubject: {_selected.Subject}\nDate: {_selected.DisplayDate}\n\n{_selected.BodyText}";
        await new ComposeWindow(_api, "", subject, body).ShowDialog(this);
    }

    private async void Star_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        try { await _api.SetFlagsAsync(_selected.Uid, _folder, flagged: !_selected.Flagged); _selected.Flagged = !_selected.Flagged; await LoadMessagesAsync(); }
        catch (Exception ex) { await ShowInfoAsync("Could not update message", ex.Message); }
    }

    private async void Unread_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        try { await _api.SetFlagsAsync(_selected.Uid, _folder, seen: false); await LoadMessagesAsync(); await LoadFoldersAsync(); }
        catch (Exception ex) { await ShowInfoAsync("Could not update message", ex.Message); }
    }

    private async void Archive_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        try { await _api.MoveAsync(_selected.Uid, _folder, "Archive"); ReaderView.IsVisible = false; ReaderEmpty.IsVisible = true; await LoadMessagesAsync(); await LoadFoldersAsync(); }
        catch (Exception ex) { await ShowInfoAsync("Could not archive message", ex.Message); }
    }

    private async void Delete_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        try
        {
            if (!_folder.Equals("Trash", StringComparison.OrdinalIgnoreCase)) await _api.MoveAsync(_selected.Uid, _folder, "Trash"); else await _api.DeleteAsync(_selected.Uid, _folder);
            ReaderView.IsVisible = false; ReaderEmpty.IsVisible = true; await LoadMessagesAsync(); await LoadFoldersAsync();
        }
        catch (Exception ex) { await ShowInfoAsync("Could not delete message", ex.Message); }
    }

    private async void ExternalSetup_Click(object? sender, RoutedEventArgs e)
    {
        var dialog = new ExternalSetupWindow(_api);
        var address = await dialog.ShowDialog<string?>(this);
        if (!string.IsNullOrWhiteSpace(address)) { EmailBox.Text = address; ShowLoginError("Account verified and remembered. Enter the mailbox password once more to open it.", false); }
    }

    private async void Account_Click(object? sender, RoutedEventArgs e)
    {
        var identity = new Identity(_api.Address, "");
        try { identity = await _api.GetIdentityAsync(); } catch { }
        await ShowInfoAsync("Account", $"{identity.DisplayName}\n{identity.Address}\n\n{(_api.IsExternalSession ? "Connected mailbox" : "iMail hosted mailbox")}\n\nUse Settings for account information, or Sign out to change accounts.");
    }

    private async void Settings_Click(object? sender, RoutedEventArgs e)
    {
        await ShowInfoAsync("iMail settings", $"Signed in as {_api.Address}\n\nDesktop iMail uses the secure Mailbox-DNS API and realtime WebSocket events. It does not persist your mailbox password. Hosted and previously connected mailboxes use the same interface.\n\nAPI: https://api.ithute.co.ls/api/v1");
    }

    private async void Logout_Click(object? sender, RoutedEventArgs e)
    {
        _realtimeCts?.Cancel();
        await _api.LogoutAsync(); _messages.Clear(); MailView.IsVisible = false; LoginView.IsVisible = true; ReaderView.IsVisible = false; ReaderEmpty.IsVisible = true; EmailBox.Focus();
    }

    private void ApplyResponsiveLayout()
    {
        if (Bounds.Width < 1080) { DesktopGrid.ColumnDefinitions[0].Width = new GridLength(0); DesktopGrid.ColumnDefinitions[1].Width = new GridLength(360); }
        else if (Bounds.Width < 1280) { DesktopGrid.ColumnDefinitions[0].Width = new GridLength(205); DesktopGrid.ColumnDefinitions[1].Width = new GridLength(360); }
        else { DesktopGrid.ColumnDefinitions[0].Width = new GridLength(240); DesktopGrid.ColumnDefinitions[1].Width = new GridLength(390); }
    }

    private void ShowLoginError(string message, bool error = true) { LoginError.Text = message; LoginError.Foreground = new SolidColorBrush(Color.Parse(error ? "#B42318" : "#064A34")); LoginError.IsVisible = true; }
    private static string FolderLabel(string name) => name.ToUpperInvariant() switch { "INBOX" => "Inbox", "SENT" => "Sent", "DRAFTS" => "Drafts", "TRASH" => "Trash", "JUNK" or "SPAM" => "Spam", _ => name };

    private async Task ShowInfoAsync(string title, string message)
    {
        var ok = new Button { Content = "OK", Classes = { "primary" }, Width = 92, HorizontalContentAlignment = HorizontalAlignment.Center };
        var window = new Window { Title = title, Width = 430, MinHeight = 210, SizeToContent = SizeToContent.Height, WindowStartupLocation = WindowStartupLocation.CenterOwner, CanResize = false };
        ok.Click += (_, _) => window.Close();
        window.Content = new StackPanel { Margin = new Thickness(26), Spacing = 18, Children = { new TextBlock { Text = title, FontSize = 21, FontWeight = FontWeight.SemiBold }, new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray }, ok } };
        await window.ShowDialog(this);
    }
}
