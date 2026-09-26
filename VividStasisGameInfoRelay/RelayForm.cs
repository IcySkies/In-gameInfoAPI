using System.Drawing;
using System.Windows.Forms;

internal sealed class RelayForm : Form
{
    private readonly Relay _relay;
    private readonly CancellationTokenSource _stop;
    private readonly Label _status = new();
    private readonly Label _game = new();
    private readonly Label _subscribers = new();
    private readonly Label _ports = new();
    private readonly Label _path = new();
    private readonly System.Windows.Forms.Timer _timer = new() { Interval = 500 };

    public RelayForm(Relay relay, CancellationTokenSource stop)
    {
        _relay = relay;
        _stop = stop;
        Text = "VividStasis Game Info Relay";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(620, 230);
        MinimumSize = new Size(620, 230);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;

        var title = new Label { Text = "VividStasis Game Info Relay", AutoSize = true, Font = new Font(Font, FontStyle.Bold), Location = new Point(20, 18) };
        _status.Location = new Point(20, 55); _status.AutoSize = true;
        _game.Location = new Point(20, 85); _game.AutoSize = true;
        _subscribers.Location = new Point(20, 115); _subscribers.AutoSize = true;
        _ports.Location = new Point(20, 145); _ports.AutoSize = true;
        _path.Location = new Point(20, 175); _path.AutoSize = true;
        Controls.AddRange([title, _status, _game, _subscribers, _ports, _path]);
        FormClosing += (_, _) => _stop.Cancel();
        _timer.Tick += (_, _) => RefreshState();
        _timer.Start();
        RefreshState();
    }

    private void RefreshState()
    {
        _status.Text = $"Status: {_relay.Status}";
        _game.Text = $"Game connection: {(_relay.GameConnected ? "Connected" : "Waiting")}";
        _subscribers.Text = $"Subscribers: {_relay.SubscriberCount}";
        _ports.Text = $"Game: 127.0.0.1:{_relay.GamePort}    Subscribers: 127.0.0.1:{_relay.SubscriberPort}";
        _path.Text = "Close this window to stop the relay.";
    }

    public void ShowRelayError(string message)
    {
        if (IsDisposed) return;
        BeginInvoke(() => MessageBox.Show(this, message, "Relay failed", MessageBoxButtons.OK, MessageBoxIcon.Error));
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _timer.Dispose();
        base.Dispose(disposing);
    }
}
