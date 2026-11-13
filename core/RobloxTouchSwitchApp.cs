using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Management;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace RobloxTouchscreenSwitch
{
    public class TouchDeviceRecord
    {
        public string Name { get; set; }
        public string DeviceID { get; set; }
        public string Status { get; set; }
        public uint ConfigManagerErrorCode { get; set; }
    }

    public class MainForm : Form
    {
        private Panel headerBanner;
        private Label lblAppTitle;
        private Label lblStatusTitle;
        private Label lblStatusSubtitle;
        private Button btnMouseMode;
        private Button btnRestoreTouch;
        private Button btnRefresh;
        private Button btnOpenLogFile;
        private TextBox txtLogViewer;
        private Label lblFooterHint;

        private readonly string DataDir = @"C:\ProgramData\RobloxTouchscreenSwitch";
        private readonly string LogPath = @"C:\ProgramData\RobloxTouchscreenSwitch\activity.log";
        private readonly string StatusPath = @"C:\ProgramData\RobloxTouchscreenSwitch\status.json";
        private readonly string ConfigPath = @"C:\Program Files\RobloxTouchscreenSwitch\config.json";

        private readonly string TaskDisable = @"\RobloxTouchscreenSwitch\DisableTouchscreen";
        private readonly string TaskEnable  = @"\RobloxTouchscreenSwitch\EnableTouchscreen";

        private bool isBusy = false;

        public MainForm(string[] args)
        {
            InitializeComponent();
            EnsureDataDir();
            AppendLocalLog("INFO", "Roblox Touchscreen Switch GUI launched by user '" + Environment.UserName + "'.");
            RefreshDeviceStateAndLogs();

            // Support optional CLI quick-launch arguments (--mouse or --touch) for Xbox / Handheld macros
            if (args != null && args.Length > 0)
            {
                string arg0 = args[0].Trim().ToLowerInvariant();
                if (arg0 == "--mouse" || arg0 == "/mouse")
                {
                    this.Shown += async (s, e) => { await TriggerScheduledTaskAsync(TaskDisable, "MOUSE MODE (Disable Touchscreen)"); };
                }
                else if (arg0 == "--touch" || arg0 == "/touch")
                {
                    this.Shown += async (s, e) => { await TriggerScheduledTaskAsync(TaskEnable, "RESTORE TOUCH (Enable Touchscreen)"); };
                }
            }
        }

        private void InitializeComponent()
        {
            this.Text = "Roblox Touchscreen Switch";
            this.Size = new Size(760, 620);
            this.MinimumSize = new Size(680, 560);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(15, 23, 42); // Slate 900
            this.ForeColor = Color.FromArgb(248, 250, 252);
            this.Font = new Font("Segoe UI", 10.5F, FontStyle.Regular);
            this.KeyPreview = true;
            this.KeyDown += MainForm_KeyDown;

            string icoPath = @"C:\Program Files\RobloxTouchscreenSwitch\RobloxTouchSwitch.ico";
            if (File.Exists(icoPath))
            {
                try { this.Icon = new Icon(icoPath); } catch { }
            }

            // Top Title & Status Banner
            headerBanner = new Panel();
            headerBanner.Dock = DockStyle.Top;
            headerBanner.Height = 128;
            headerBanner.Padding = new Padding(20, 14, 20, 14);
            headerBanner.BackColor = Color.FromArgb(30, 41, 59);

            lblAppTitle = new Label();
            lblAppTitle.Text = "ROBLOX TOUCHSCREEN SWITCH  •  HANDHELD INPUT CONTROLLER";
            lblAppTitle.Font = new Font("Segoe UI", 9.5F, FontStyle.Bold);
            lblAppTitle.ForeColor = Color.FromArgb(148, 163, 184);
            lblAppTitle.AutoSize = false;
            lblAppTitle.Dock = DockStyle.Top;
            lblAppTitle.Height = 24;

            lblStatusTitle = new Label();
            lblStatusTitle.Text = "CHECKING TOUCHSCREEN STATUS...";
            lblStatusTitle.Font = new Font("Segoe UI", 18F, FontStyle.Bold);
            lblStatusTitle.ForeColor = Color.White;
            lblStatusTitle.AutoSize = false;
            lblStatusTitle.Dock = DockStyle.Top;
            lblStatusTitle.Height = 42;
            lblStatusTitle.TextAlign = ContentAlignment.MiddleLeft;

            lblStatusSubtitle = new Label();
            lblStatusSubtitle.Text = "Inspecting HID-compliant touch screen state in Windows Device Manager...";
            lblStatusSubtitle.Font = new Font("Segoe UI", 10.5F, FontStyle.Regular);
            lblStatusSubtitle.ForeColor = Color.FromArgb(226, 232, 240);
            lblStatusSubtitle.AutoSize = false;
            lblStatusSubtitle.Dock = DockStyle.Fill;
            lblStatusSubtitle.TextAlign = ContentAlignment.MiddleLeft;

            headerBanner.Controls.Add(lblStatusSubtitle);
            headerBanner.Controls.Add(lblStatusTitle);
            headerBanner.Controls.Add(lblAppTitle);

            // Center Main Layout Table
            TableLayoutPanel mainLayout = new TableLayoutPanel();
            mainLayout.Dock = DockStyle.Fill;
            mainLayout.Padding = new Padding(20, 18, 20, 14);
            mainLayout.ColumnCount = 2;
            mainLayout.RowCount = 4;
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50F));
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50F));
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 165F)); // Two huge handheld buttons
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 46F));  // Utility toolbar row
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));  // Activity log box
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28F));  // Gamepad/Keyboard hint bar

            // Large Button 1: MOUSE MODE
            btnMouseMode = new Button();
            btnMouseMode.Dock = DockStyle.Fill;
            btnMouseMode.Margin = new Padding(0, 0, 10, 12);
            btnMouseMode.FlatStyle = FlatStyle.Flat;
            btnMouseMode.FlatAppearance.BorderSize = 2;
            btnMouseMode.FlatAppearance.BorderColor = Color.FromArgb(56, 189, 248);
            btnMouseMode.BackColor = Color.FromArgb(3, 105, 161); // Sky 700
            btnMouseMode.ForeColor = Color.White;
            btnMouseMode.Font = new Font("Segoe UI", 15F, FontStyle.Bold);
            btnMouseMode.Cursor = Cursors.Hand;
            btnMouseMode.TabIndex = 0;
            btnMouseMode.TabStop = false;
            btnMouseMode.Text = "🖱️  MOUSE MODE\r\n(DISABLE TOUCHSCREEN)\r\n\r\nFixes Roblox Fling Things & People";
            btnMouseMode.Click += async (s, e) =>
            {
                await TriggerScheduledTaskAsync(TaskDisable, "MOUSE MODE (Disable Touchscreen)");
            };

            // Large Button 2: RESTORE TOUCH
            btnRestoreTouch = new Button();
            btnRestoreTouch.Dock = DockStyle.Fill;
            btnRestoreTouch.Margin = new Padding(10, 0, 0, 12);
            btnRestoreTouch.FlatStyle = FlatStyle.Flat;
            btnRestoreTouch.FlatAppearance.BorderSize = 2;
            btnRestoreTouch.FlatAppearance.BorderColor = Color.FromArgb(74, 222, 128);
            btnRestoreTouch.BackColor = Color.FromArgb(21, 128, 61); // Green 700
            btnRestoreTouch.ForeColor = Color.White;
            btnRestoreTouch.Font = new Font("Segoe UI", 15F, FontStyle.Bold);
            btnRestoreTouch.Cursor = Cursors.Hand;
            btnRestoreTouch.TabIndex = 1;
            btnRestoreTouch.TabStop = false;
            btnRestoreTouch.Text = "👆  RESTORE TOUCH\r\n(ENABLE TOUCHSCREEN)\r\n\r\nRestores Normal Handheld Touch";
            btnRestoreTouch.Click += async (s, e) =>
            {
                await TriggerScheduledTaskAsync(TaskEnable, "RESTORE TOUCH (Enable Touchscreen)");
            };

            // Utility Toolbar Panel spanning 2 columns
            FlowLayoutPanel toolbarPanel = new FlowLayoutPanel();
            toolbarPanel.Dock = DockStyle.Fill;
            toolbarPanel.FlowDirection = FlowDirection.LeftToRight;
            toolbarPanel.Margin = new Padding(0, 0, 0, 6);

            Label lblLogHeader = new Label();
            lblLogHeader.Text = "Activity & Diagnostic Log:";
            lblLogHeader.Font = new Font("Segoe UI", 10F, FontStyle.Bold);
            lblLogHeader.ForeColor = Color.FromArgb(148, 163, 184);
            lblLogHeader.AutoSize = true;
            lblLogHeader.Margin = new Padding(0, 8, 16, 0);

            btnRefresh = new Button();
            btnRefresh.Text = "🔄 Refresh Status";
            btnRefresh.Size = new Size(175, 32);
            btnRefresh.FlatStyle = FlatStyle.Flat;
            btnRefresh.FlatAppearance.BorderSize = 1;
            btnRefresh.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
            btnRefresh.BackColor = Color.FromArgb(30, 41, 59);
            btnRefresh.ForeColor = Color.FromArgb(226, 232, 240);
            btnRefresh.Font = new Font("Segoe UI", 9.5F, FontStyle.Regular);
            btnRefresh.TabIndex = 2;
            btnRefresh.Click += (s, e) => RefreshDeviceStateAndLogs();

            btnOpenLogFile = new Button();
            btnOpenLogFile.Text = "📄 Open Full Log File";
            btnOpenLogFile.Size = new Size(175, 32);
            btnOpenLogFile.FlatStyle = FlatStyle.Flat;
            btnOpenLogFile.FlatAppearance.BorderSize = 1;
            btnOpenLogFile.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
            btnOpenLogFile.BackColor = Color.FromArgb(30, 41, 59);
            btnOpenLogFile.ForeColor = Color.FromArgb(226, 232, 240);
            btnOpenLogFile.Font = new Font("Segoe UI", 9.5F, FontStyle.Regular);
            btnOpenLogFile.Margin = new Padding(10, 3, 0, 3);
            btnOpenLogFile.TabIndex = 3;
            btnOpenLogFile.Click += (s, e) =>
            {
                try
                {
                    if (File.Exists(LogPath))
                    {
                        Process.Start("notepad.exe", "\"" + LogPath + "\"");
                    }
                    else
                    {
                        MessageBox.Show("Log file has not been created yet.", "Activity Log", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Could not open log file: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            };

            toolbarPanel.Controls.Add(lblLogHeader);
            toolbarPanel.Controls.Add(btnRefresh);
            toolbarPanel.Controls.Add(btnOpenLogFile);

            // Activity Log Textbox
            txtLogViewer = new TextBox();
            txtLogViewer.Multiline = true;
            txtLogViewer.ReadOnly = true;
            txtLogViewer.ScrollBars = ScrollBars.Vertical;
            txtLogViewer.Dock = DockStyle.Fill;
            txtLogViewer.BackColor = Color.FromArgb(9, 14, 26);
            txtLogViewer.ForeColor = Color.FromArgb(203, 213, 225);
            txtLogViewer.Font = new Font("Consolas", 9.5F, FontStyle.Regular);
            txtLogViewer.BorderStyle = BorderStyle.FixedSingle;
            txtLogViewer.TabStop = false;

            // Footer Hint
            lblFooterHint = new Label();
            lblFooterHint.Dock = DockStyle.Fill;
            lblFooterHint.Text = "Safe Chords (Window Focused Only): [Ctrl+Alt+Shift+M] = Mouse Mode  |  [Ctrl+Alt+Shift+T] = Restore Touch  |  [Ctrl+Alt+Shift+R] = Refresh";
            lblFooterHint.Font = new Font("Segoe UI", 8.75F, FontStyle.Regular);
            lblFooterHint.ForeColor = Color.FromArgb(148, 163, 184);
            lblFooterHint.TextAlign = ContentAlignment.MiddleLeft;

            mainLayout.Controls.Add(btnMouseMode, 0, 0);
            mainLayout.Controls.Add(btnRestoreTouch, 1, 0);
            mainLayout.Controls.Add(toolbarPanel, 0, 1);
            mainLayout.SetColumnSpan(toolbarPanel, 2);
            mainLayout.Controls.Add(txtLogViewer, 0, 2);
            mainLayout.SetColumnSpan(txtLogViewer, 2);
            mainLayout.Controls.Add(lblFooterHint, 0, 3);
            mainLayout.SetColumnSpan(lblFooterHint, 2);

            this.Controls.Add(mainLayout);
            this.Controls.Add(headerBanner);
        }

        private void MainForm_KeyDown(object sender, KeyEventArgs e)
        {
            if (isBusy) return;
            // Require deliberate 4-key modifier chord (Ctrl + Alt + Shift) so common game keys
            // (WASD, 1/2, M, T, Space, Enter, F5) and controller buttons never trigger accidental toggles.
            if (e.Control && e.Alt && e.Shift)
            {
                if (e.KeyCode == Keys.M)
                {
                    e.SuppressKeyPress = true;
                    btnMouseMode.PerformClick();
                }
                else if (e.KeyCode == Keys.T)
                {
                    e.SuppressKeyPress = true;
                    btnRestoreTouch.PerformClick();
                }
                else if (e.KeyCode == Keys.R)
                {
                    e.SuppressKeyPress = true;
                    RefreshDeviceStateAndLogs();
                }
            }
        }

        private void EnsureDataDir()
        {
            try
            {
                if (!Directory.Exists(DataDir))
                {
                    Directory.CreateDirectory(DataDir);
                }
            }
            catch { }
        }

        private void AppendLocalLog(string level, string message)
        {
            try
            {
                string line = string.Format("[{0}] [GUI:{1}] [{2}] {3}{4}",
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                    Environment.UserName,
                    level,
                    message,
                    Environment.NewLine);
                File.AppendAllText(LogPath, line, Encoding.UTF8);
            }
            catch { }
        }

        private string GetPinnedInstanceId()
        {
            try
            {
                if (File.Exists(ConfigPath))
                {
                    string json = File.ReadAllText(ConfigPath, Encoding.UTF8);
                    Match m = Regex.Match(json, "\"PinnedInstanceId\"\\s*:\\s*\"([^\"]*)\"");
                    if (m.Success && !string.IsNullOrWhiteSpace(m.Groups[1].Value))
                    {
                        return m.Groups[1].Value.Trim();
                    }
                }
            }
            catch { }
            return null;
        }

        private List<TouchDeviceRecord> QueryTouchDevices()
        {
            List<TouchDeviceRecord> list = new List<TouchDeviceRecord>();
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    @"root\CIMV2",
                    "SELECT Name, DeviceID, Status, ConfigManagerErrorCode FROM Win32_PnPEntity WHERE Name = 'HID-compliant touch screen'"))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        TouchDeviceRecord rec = new TouchDeviceRecord
                        {
                            Name = Convert.ToString(obj["Name"] ?? ""),
                            DeviceID = Convert.ToString(obj["DeviceID"] ?? ""),
                            Status = Convert.ToString(obj["Status"] ?? ""),
                            ConfigManagerErrorCode = obj["ConfigManagerErrorCode"] != null
                                ? Convert.ToUInt32(obj["ConfigManagerErrorCode"])
                                : 0u
                        };
                        list.Add(rec);
                    }
                }
            }
            catch (Exception ex)
            {
                AppendLocalLog("WARN", "WMI query warning: " + ex.Message);
            }

            string pinned = GetPinnedInstanceId();
            if (!string.IsNullOrEmpty(pinned) && list.Count > 1)
            {
                List<TouchDeviceRecord> filtered = list.FindAll(d => string.Equals(d.DeviceID, pinned, StringComparison.OrdinalIgnoreCase));
                if (filtered.Count == 1)
                {
                    return filtered;
                }
            }
            return list;
        }

        private void RefreshDeviceStateAndLogs()
        {
            List<TouchDeviceRecord> devices = QueryTouchDevices();

            if (devices.Count == 0)
            {
                headerBanner.BackColor = Color.FromArgb(153, 27, 27); // Red 800
                lblStatusTitle.Text = "⚠️ TOUCHSCREEN DEVICE NOT FOUND";
                lblStatusSubtitle.Text = "No 'HID-compliant touch screen' was detected in Device Manager. Check driver status or run Recovery.";
            }
            else if (devices.Count > 1)
            {
                headerBanner.BackColor = Color.FromArgb(180, 83, 9); // Amber 700
                lblStatusTitle.Text = "🛑 MULTIPLE TOUCHSCREENS FOUND (" + devices.Count + ") — ADMIN REQUIRED";
                lblStatusSubtitle.Text = "Safeguard active: Refusing to guess between multiple HID touch devices. Administrator intervention required.";
            }
            else
            {
                TouchDeviceRecord dev = devices[0];
                bool isDisabled = (dev.ConfigManagerErrorCode == 22) || !string.Equals(dev.Status, "OK", StringComparison.OrdinalIgnoreCase);

                if (isDisabled)
                {
                    headerBanner.BackColor = Color.FromArgb(3, 105, 161); // Sky Blue 700
                    lblStatusTitle.Text = "🖱️ MOUSE MODE ACTIVE  (TOUCHSCREEN OFF)";
                    lblStatusSubtitle.Text = "Ready for Roblox (Fling Things and People). External mouse clicks & grabbing work normally. [" + dev.DeviceID + "]";
                }
                else
                {
                    headerBanner.BackColor = Color.FromArgb(21, 128, 61); // Green 700
                    lblStatusTitle.Text = "👆 TOUCHSCREEN ENABLED  (NORMAL HANDHELD MODE)";
                    lblStatusSubtitle.Text = "Touchscreen is ON and working normally. Click MOUSE MODE before playing Roblox with an external mouse. [" + dev.DeviceID + "]";
                }
            }

            LoadTailOfActivityLog();
        }

        private void LoadTailOfActivityLog()
        {
            try
            {
                if (File.Exists(LogPath))
                {
                    string[] lines = File.ReadAllLines(LogPath, Encoding.UTF8);
                    int start = Math.Max(0, lines.Length - 80);
                    StringBuilder sb = new StringBuilder();
                    for (int i = start; i < lines.Length; i++)
                    {
                        sb.AppendLine(lines[i]);
                    }
                    txtLogViewer.Text = sb.ToString();
                    txtLogViewer.SelectionStart = txtLogViewer.Text.Length;
                    txtLogViewer.ScrollToCaret();
                }
                else
                {
                    txtLogViewer.Text = "Activity log initialized. Click MOUSE MODE or RESTORE TOUCH to record events.";
                }
            }
            catch (Exception ex)
            {
                txtLogViewer.Text = "Unable to read activity log: " + ex.Message;
            }
        }

        private async Task TriggerScheduledTaskAsync(string taskFullName, string friendlyActionName)
        {
            if (isBusy) return;

            // Pre-check hardware safeguards in GUI so we can display an immediate, helpful message if needed
            List<TouchDeviceRecord> preCheck = QueryTouchDevices();
            if (preCheck.Count == 0)
            {
                AppendLocalLog("ERROR", "Attempted '" + friendlyActionName + "', but no 'HID-compliant touch screen' device was found in Device Manager.");
                RefreshDeviceStateAndLogs();
                MessageBox.Show(
                    "The 'HID-compliant touch screen' device could not be found in Windows Device Manager.\r\n\r\n" +
                    "What to check:\r\n" +
                    "1. Ensure the handheld screen is powered on and not detached.\r\n" +
                    "2. Ask an Administrator to open Device Manager -> View -> Show hidden devices -> Human Interface Devices.\r\n" +
                    "3. Run 'Scan for hardware changes' or run the Emergency Recovery script.",
                    "Touchscreen Device Not Found",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return;
            }

            if (preCheck.Count > 1)
            {
                StringBuilder ids = new StringBuilder();
                foreach (var d in preCheck) ids.AppendLine(" • " + d.DeviceID + " (Status: " + d.Status + ")");
                AppendLocalLog("ERROR", "Safeguard halted '" + friendlyActionName + "': Multiple (" + preCheck.Count + ") matching touchscreen devices found.");
                RefreshDeviceStateAndLogs();
                MessageBox.Show(
                    "SAFETY STOP: Multiple (" + preCheck.Count + ") 'HID-compliant touch screen' devices were detected:\r\n\r\n" +
                    ids.ToString() + "\r\n" +
                    "To protect your system, Roblox Touchscreen Switch will never guess or disable unrelated HID devices.\r\n\r\n" +
                    "Please ask the Administrator to re-run Install-RobloxTouchSwitch.bat to pin the exact hardware InstanceId in config.json.",
                    "Administrator Intervention Required",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            isBusy = true;
            btnMouseMode.Enabled = false;
            btnRestoreTouch.Enabled = false;
            lblStatusTitle.Text = "⏳ APPLYING " + friendlyActionName.ToUpperInvariant() + "...";
            lblStatusSubtitle.Text = "Triggering restricted SYSTEM Scheduled Task (" + taskFullName + ")...";
            AppendLocalLog("INFO", "Requesting Scheduled Task '" + taskFullName + "' for '" + friendlyActionName + "'.");

            try
            {
                int exitCode = await Task.Run(() =>
                {
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = "schtasks.exe",
                        Arguments = "/Run /TN \"" + taskFullName + "\"",
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    };
                    using (Process p = Process.Start(psi))
                    {
                        p.WaitForExit(8000);
                        return p.ExitCode;
                    }
                });

                if (exitCode != 0)
                {
                    AppendLocalLog("ERROR", "schtasks.exe /Run failed for '" + taskFullName + "' with exit code " + exitCode + ". Ensure the Administrator installer was run.");
                    MessageBox.Show(
                        "Could not trigger Scheduled Task '" + taskFullName + "' (Exit Code " + exitCode + ").\r\n\r\n" +
                        "Please ask an Administrator to run 'Install-RobloxTouchSwitch.bat' to register and grant permissions for the tasks.",
                        "Scheduled Task Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                else
                {
                    // Poll up to 4.5 seconds for the SYSTEM task to toggle the PnP device and write status.json
                    bool targetDisable = taskFullName.IndexOf("Disable", StringComparison.OrdinalIgnoreCase) >= 0;
                    for (int attempt = 0; attempt < 15; attempt++)
                    {
                        await Task.Delay(300);
                        List<TouchDeviceRecord> current = QueryTouchDevices();
                        if (current.Count == 1)
                        {
                            bool nowDisabled = (current[0].ConfigManagerErrorCode == 22) ||
                                               !string.Equals(current[0].Status, "OK", StringComparison.OrdinalIgnoreCase);
                            if (targetDisable == nowDisabled)
                            {
                                break;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                AppendLocalLog("ERROR", "Exception running scheduled task: " + ex.Message);
                MessageBox.Show("Unexpected error triggering Scheduled Task:\r\n" + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                isBusy = false;
                btnMouseMode.Enabled = true;
                btnRestoreTouch.Enabled = true;
                RefreshDeviceStateAndLogs();
            }
        }

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm(args));
        }
    }
}
