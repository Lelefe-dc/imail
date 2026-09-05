using Avalonia.Controls;
using Avalonia.Interactivity;

namespace IMail.Desktop;

public partial class ExternalSetupWindow : Window
{
    private readonly IMailApiClient _api;

    public ExternalSetupWindow(IMailApiClient api)
    {
        InitializeComponent();
        _api = api;
    }

    private void EmailBox_LostFocus(object? sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(ImapHostBox.Text) && string.IsNullOrWhiteSpace(SmtpHostBox.Text)) ApplyDefaults();
    }

    private void Defaults_Click(object? sender, RoutedEventArgs e) => ApplyDefaults();

    private void ApplyDefaults()
    {
        var email = EmailBox.Text?.Trim().ToLowerInvariant() ?? "";
        var at = email.LastIndexOf('@');
        if (at < 1 || at == email.Length - 1) { StatusText.Text = "Enter the email address first."; return; }
        var domain = email[(at + 1)..];
        UsernameBox.Text = email;
        ImapHostBox.Text = $"mail.{domain}";
        ImapPortBox.Text = "993";
        ImapSecurityBox.SelectedIndex = 0;
        SmtpHostBox.Text = $"mail.{domain}";
        SmtpPortBox.Text = "587";
        SmtpSecurityBox.SelectedIndex = 1;
        StatusText.Text = "Standard secure settings applied. iMail will also try common secure alternatives if needed.";
    }

    private async void Connect_Click(object? sender, RoutedEventArgs e)
    {
        var email = EmailBox.Text?.Trim().ToLowerInvariant() ?? "";
        var password = PasswordBox.Text ?? "";
        if (!email.Contains('@') || password.Length == 0) { StatusText.Text = "Enter a valid email address and mailbox password."; return; }
        Progress.IsVisible = true;
        StatusText.Text = "Checking secure incoming and outgoing mail…";
        try
        {
            var username = string.IsNullOrWhiteSpace(UsernameBox.Text) ? email : UsernameBox.Text!.Trim();
            var name = NameBox.Text?.Trim() ?? "";
            var candidates = BuildCandidates(email, username, name, password);
            Exception? last = null;
            foreach (var settings in candidates)
            {
                try
                {
                    StatusText.Text = $"Checking {settings.ImapHost} and {settings.SmtpHost}…";
                    await _api.RegisterExternalAsync(settings);
                    StatusText.Text = "Mailbox verified and remembered.";
                    Close(email);
                    return;
                }
                catch (Exception ex) { last = ex; }
            }
            StatusText.Text = last?.Message ?? "The mailbox could not be verified. Review the server settings and try again.";
        }
        finally { Progress.IsVisible = false; }
    }

    private List<ExternalAccountSettings> BuildCandidates(string email, string username, string name, string password)
    {
        var manualImapHost = ImapHostBox.Text?.Trim() ?? "";
        var manualSmtpHost = SmtpHostBox.Text?.Trim() ?? "";
        var manualImapPort = int.TryParse(ImapPortBox.Text, out var ip) ? ip : 993;
        var manualSmtpPort = int.TryParse(SmtpPortBox.Text, out var sp) ? sp : 587;
        var manualImapSecurity = (ImapSecurityBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "ssl";
        var manualSmtpSecurity = (SmtpSecurityBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "starttls";
        var list = new List<ExternalAccountSettings>();
        if (manualImapHost.Length > 0 && manualSmtpHost.Length > 0)
            list.Add(new(email, password, username, name, manualImapHost, manualImapPort, manualImapSecurity, manualSmtpHost, manualSmtpPort, manualSmtpSecurity));

        var domain = email[(email.LastIndexOf('@') + 1)..];
        var standards = new[]
        {
            new ExternalAccountSettings(email,password,username,name,$"mail.{domain}",993,"ssl",$"mail.{domain}",587,"starttls"),
            new ExternalAccountSettings(email,password,username,name,$"mail.{domain}",993,"ssl",$"mail.{domain}",465,"ssl"),
            new ExternalAccountSettings(email,password,username,name,$"imap.{domain}",993,"ssl",$"smtp.{domain}",587,"starttls"),
            new ExternalAccountSettings(email,password,username,name,$"imap.{domain}",993,"ssl",$"smtp.{domain}",465,"ssl")
        };
        foreach (var item in standards)
            if (!list.Any(x => x.ImapHost == item.ImapHost && x.ImapPort == item.ImapPort && x.SmtpHost == item.SmtpHost && x.SmtpPort == item.SmtpPort)) list.Add(item);
        return list;
    }

    private void Cancel_Click(object? sender, RoutedEventArgs e) => Close(null);
}
