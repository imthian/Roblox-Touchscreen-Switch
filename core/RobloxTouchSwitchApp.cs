using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
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

    [DataContract]
    public class AppConfigData
    {
        [DataMember] public string AppName { get; set; }
        [DataMember] public string Version { get; set; }
        [DataMember] public string PinnedInstanceId { get; set; }
        [DataMember] public string[] PinnedInstanceIds { get; set; }
    }

    [DataContract]
    public class WorkerStatusReport
    {
        [DataMember] public string Version { get; set; }
        [DataMember] public string Timestamp { get; set; }
        [DataMember] public long TimestampUtc { get; set; }
        [DataMember] public string LastAction { get; set; }
        [DataMember] public string ResultCode { get; set; }
        [DataMember] public string TouchState { get; set; }
        [DataMember] public string DeviceStatus { get; set; }
        [DataMember] public int ErrorCode { get; set; }
        [DataMember] public string InstanceId { get; set; }
        [DataMember] public int MatchedCount { get; set; }
        [DataMember] public string Message { get; set; }
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
        private Button btnOpenSystemLog;
        private Button btnOpenUserLog;
        private TextBox txtLogViewer;
        private Label lblFooterHint;

        private readonly string InstallDir;
        private readonly string SystemDataDir;
        private readonly string SystemLogPath;
        private readonly string StatusPath;
        private readonly string ConfigPath;
        private readonly string AppVersion;

        private readonly string UserDataDir;
        private readonly string UserLogPath;

        private readonly string TaskDisable = @"\RobloxTouchscreenSwitch\DisableTouchscreen";
        private readonly string TaskEnable  = @"\RobloxTouchscreenSwitch\EnableTouchscreen";

        private bool isBusy = false;

        public MainForm(string[] args)
        {
            InstallDir    = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "RobloxTouchscreenSwitch");
            SystemDataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "RobloxTouchscreenSwitch");
            SystemLogPath = Path.Combine(SystemDataDir, "system-activity.log");
            StatusPath    = Path.Combine(SystemDataDir, "status.json");
            ConfigPath    = Path.Combine(InstallDir, "config.json");

            string verFile = Path.Combine(InstallDir, "VERSION");
            AppVersion = File.Exists(verFile) ? File.ReadAllText(verFile, Encoding.UTF8).Trim() : "1.2.1";

            UserDataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RobloxTouchscreenSwitch");
            UserLogPath = Path.Combine(UserDataDir, "gui-activity.log");

            InitializeComponent();
            EnsureUserDir();
            AppendUserLog("INFO", "Roblox Touchscreen Switch GUI v" + AppVersion + " launched by user '" + Environment.UserName + "'.");
            RefreshDeviceStateAndLogs();

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
            this.Text = "Roblox Touchscreen Switch v" + AppVersion;
            this.Size = new Size(760, 620);
            this.MinimumSize = new Size(680, 560);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(15, 23, 42);
            this.ForeColor = Color.FromArgb(248, 250, 252);
            this.Font = new Font("Segoe UI", 10.5F, FontStyle.Regular);
            this.KeyPreview = true;
            this.KeyDown += MainForm_KeyDown;

            string icoPath = Path.Combine(InstallDir, "RobloxTouchSwitch.ico");
            if (File.Exists(icoPath))
            {
                try { this.Icon = new Icon(icoPath); } catch { }
            }

            headerBanner = new Panel();
            headerBanner.Dock = DockStyle.Top;
            headerBanner.Height = 128;
            headerBanner.Padding = new Padding(20, 14, 20, 14);
            headerBanner.BackColor = Color.FromArgb(30, 41, 59);

            lblAppTitle = new Label();
            lblAppTitle.Text = "ROBLOX TOUCHSCREEN SWITCH v" + AppVersion + "  -  HANDHELD INPUT CONTROLLER";
            lblAppTitle.Font = new Font("Segoe UI", 9.5F, FontStyle.Bold);
            lblAppTitle.ForeColor = Color.FromArgb(148, 163, 184);
            lblAppTitle.AutoSize = false;
            lblAppTitle.Dock = DockStyle.Top;
            lblAppTitle.Height = 24;

            lblStatusTitle = new Label();
            lblStatusTitle.Text = "CHECKING TOUCHSCREEN STATUS...";
            lblStatusTitle.Font = new Font("Segoe UI", 17.5F, FontStyle.Bold);
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

            TableLayoutPanel mainLayout = new TableLayoutPanel();
            mainLayout.Dock = DockStyle.Fill;
            mainLayout.Padding = new Padding(20, 18, 20, 14);
            mainLayout.ColumnCount = 2;
            mainLayout.RowCount = 4;
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50F));
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50F));
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 165F));
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 46F));
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            mainLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28F));

            btnMouseMode = new Button();
            btnMouseMode.Dock = DockStyle.Fill;
            btnMouseMode.Margin = new Padding(0, 0, 10, 12);
            btnMouseMode.FlatStyle = FlatStyle.Flat;
            btnMouseMode.FlatAppearance.BorderSize = 2;
            btnMouseMode.FlatAppearance.BorderColor = Color.FromArgb(56, 189, 248);
            btnMouseMode.BackColor = Color.FromArgb(3, 105, 161);
            btnMouseMode.ForeColor = Color.White;
            btnMouseMode.Font = new Font("Segoe UI", 14.5F, FontStyle.Bold);
            btnMouseMode.Cursor = Cursors.Hand;
            btnMouseMode.TabIndex = 0;
            btnMouseMode.TabStop = false;
            btnMouseMode.Text = "[ MOUSE MODE ]\r\nDISABLE TOUCHSCREEN\r\n\r\nFixes Roblox External Mouse Clicks";
            btnMouseMode.Click += async (s, e) =>
            {
                await TriggerScheduledTaskAsync(TaskDisable, "MOUSE MODE (Disable Touchscreen)");
            };

            btnRestoreTouch = new Button();
            btnRestoreTouch.Dock = DockStyle.Fill;
            btnRestoreTouch.Margin = new Padding(10, 0, 0, 12);
            btnRestoreTouch.FlatStyle = FlatStyle.Flat;
            btnRestoreTouch.FlatAppearance.BorderSize = 2;
            btnRestoreTouch.FlatAppearance.BorderColor = Color.FromArgb(74, 222, 128);
            btnRestoreTouch.BackColor = Color.FromArgb(21, 128, 61);
            btnRestoreTouch.ForeColor = Color.White;
            btnRestoreTouch.Font = new Font("Segoe UI", 14.5F, FontStyle.Bold);
            btnRestoreTouch.Cursor = Cursors.Hand;
            btnRestoreTouch.TabIndex = 1;
            btnRestoreTouch.TabStop = false;
            btnRestoreTouch.Text = "[ RESTORE TOUCH ]\r\nENABLE TOUCHSCREEN\r\n\r\nRestores Normal Handheld Touch";
            btnRestoreTouch.Click += async (s, e) =>
            {
                await TriggerScheduledTaskAsync(TaskEnable, "RESTORE TOUCH (Enable Touchscreen)");
            };

            FlowLayoutPanel toolbarPanel = new FlowLayoutPanel();
            toolbarPanel.Dock = DockStyle.Fill;
            toolbarPanel.FlowDirection = FlowDirection.LeftToRight;
            toolbarPanel.Margin = new Padding(0, 0, 0, 6);

            Label lblLogHeader = new Label();
            lblLogHeader.Text = "Audit & Diagnostic Logs:";
            lblLogHeader.Font = new Font("Segoe UI", 10F, FontStyle.Bold);
            lblLogHeader.ForeColor = Color.FromArgb(148, 163, 184);
            lblLogHeader.AutoSize = true;
            lblLogHeader.Margin = new Padding(0, 8, 12, 0);

            btnRefresh = new Button();
            btnRefresh.Text = "Refresh Status";
            btnRefresh.Size = new Size(140, 32);
            btnRefresh.FlatStyle = FlatStyle.Flat;
            btnRefresh.FlatAppearance.BorderSize = 1;
            btnRefresh.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
            btnRefresh.BackColor = Color.FromArgb(30, 41, 59);
            btnRefresh.ForeColor = Color.FromArgb(226, 232, 240);
            btnRefresh.Font = new Font("Segoe UI", 9.5F, FontStyle.Regular);
            btnRefresh.TabIndex = 2;
            btnRefresh.TabStop = false;
            btnRefresh.Click += (s, e) => RefreshDeviceStateAndLogs();

            btnOpenSystemLog = new Button();
            btnOpenSystemLog.Text = "Open SYSTEM Audit Log";
            btnOpenSystemLog.Size = new Size(175, 32);
            btnOpenSystemLog.FlatStyle = FlatStyle.Flat;
            btnOpenSystemLog.FlatAppearance.BorderSize = 1;
            btnOpenSystemLog.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
            btnOpenSystemLog.BackColor = Color.FromArgb(30, 41, 59);
            btnOpenSystemLog.ForeColor = Color.FromArgb(226, 232, 240);
            btnOpenSystemLog.Font = new Font("Segoe UI", 9.5F, FontStyle.Regular);
            btnOpenSystemLog.Margin = new Padding(8, 3, 0, 3);
            btnOpenSystemLog.TabIndex = 3;
            btnOpenSystemLog.TabStop = false;
            btnOpenSystemLog.Click += (s, e) => OpenLogInNotepad(SystemLogPath, "SYSTEM Audit Log");

            btnOpenUserLog = new Button();
            btnOpenUserLog.Text = "Open User GUI Log";
            btnOpenUserLog.Size = new Size(155, 32);
            btnOpenUserLog.FlatStyle = FlatStyle.Flat;
            btnOpenUserLog.FlatAppearance.BorderSize = 1;
            btnOpenUserLog.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
            btnOpenUserLog.BackColor = Color.FromArgb(30, 41, 59);
            btnOpenUserLog.ForeColor = Color.FromArgb(226, 232, 240);
            btnOpenUserLog.Font = new Font("Segoe UI", 9.5F, FontStyle.Regular);
            btnOpenUserLog.Margin = new Padding(8, 3, 0, 3);
            btnOpenUserLog.TabIndex = 4;
            btnOpenUserLog.TabStop = false;
            btnOpenUserLog.Click += (s, e) => OpenLogInNotepad(UserLogPath, "User GUI Log");

            toolbarPanel.Controls.Add(lblLogHeader);
            toolbarPanel.Controls.Add(btnRefresh);
            toolbarPanel.Controls.Add(btnOpenSystemLog);
            toolbarPanel.Controls.Add(btnOpenUserLog);

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

        private void OpenLogInNotepad(string path, string title)
        {
            try
            {
                if (File.Exists(path))
                {
                    Process.Start("notepad.exe", "\"" + path + "\"");
                }
                else
                {
                    MessageBox.Show(title + " has not been created yet at:\r\n" + path, title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not open " + title + ": " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void MainForm_KeyDown(object sender, KeyEventArgs e)
        {
            if (isBusy) return;
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

        private void EnsureUserDir()
        {
            try
            {
                if (!Directory.Exists(UserDataDir))
                {
                    Directory.CreateDirectory(UserDataDir);
                }
            }
            catch { }
        }

        private void AppendUserLog(string level, string message)
        {
            try
            {
                if (File.Exists(UserLogPath))
                {
                    FileInfo fi = new FileInfo(UserLogPath);
                    if (fi.Length > 524288)
                    {
                        string oldPath = Path.Combine(UserDataDir, "gui-activity.old.log");
                        if (File.Exists(oldPath)) File.Delete(oldPath);
                        File.Move(UserLogPath, oldPath);
                    }
                }
                string line = string.Format("[{0}] [GUI:{1}] [{2}] {3}{4}",
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                    Environment.UserName,
                    level,
                    message,
                    Environment.NewLine);
                File.AppendAllText(UserLogPath, line, Encoding.UTF8);
            }
            catch { }
        }

        private static MemoryStream CreateBomFreeJsonStream(string path)
        {
            string text = File.ReadAllText(path, Encoding.UTF8);
            if (!string.IsNullOrEmpty(text) && text[0] == '\uFEFF')
            {
                text = text.Substring(1);
            }
            return new MemoryStream(Encoding.UTF8.GetBytes(text.Trim()));
        }

        private List<string> GetPinnedInstanceIds()
        {
            List<string> pins = new List<string>();
            try
            {
                if (File.Exists(ConfigPath))
                {
                    DataContractJsonSerializer ser = new DataContractJsonSerializer(typeof(AppConfigData));
                    using (MemoryStream ms = CreateBomFreeJsonStream(ConfigPath))
                    {
                        AppConfigData cfg = ser.ReadObject(ms) as AppConfigData;
                        if (cfg != null)
                        {
                            if (cfg.PinnedInstanceIds != null)
                            {
                                foreach (string s in cfg.PinnedInstanceIds)
                                {
                                    if (!string.IsNullOrWhiteSpace(s)) pins.Add(s.Trim());
                                }
                            }
                            if (pins.Count == 0 && !string.IsNullOrWhiteSpace(cfg.PinnedInstanceId))
                            {
                                pins.Add(cfg.PinnedInstanceId.Trim());
                            }
                        }
                    }
                }
            }
            catch { }
            return pins;
        }

        private WorkerStatusReport ReadStatusReport()
        {
            try
            {
                if (File.Exists(StatusPath))
                {
                    DataContractJsonSerializer ser = new DataContractJsonSerializer(typeof(WorkerStatusReport));
                    using (MemoryStream ms = CreateBomFreeJsonStream(StatusPath))
                    {
                        return ser.ReadObject(ms) as WorkerStatusReport;
                    }
                }
            }
            catch { }
            return null;
        }

        // Queries all present HID touchscreens; also returns whether a pinned device is missing
        private List<TouchDeviceRecord> QueryTouchDevices(out List<string> missingPins)
        {
            missingPins = new List<string>();
            List<TouchDeviceRecord> allMatched = new List<TouchDeviceRecord>();
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    @"root\CIMV2",
                    "SELECT Name, DeviceID, Status, ConfigManagerErrorCode, HardwareID, CompatibleID FROM Win32_PnPEntity WHERE PNPClass = 'HIDClass'"))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        string name = Convert.ToString(obj["Name"] ?? "");
                        bool isTouchName = string.Equals(name, "HID-compliant touch screen", StringComparison.OrdinalIgnoreCase);
                        bool isTouchUsage = false;

                        string[] hwIds = obj["HardwareID"] as string[];
                        if (hwIds != null)
                        {
                            foreach (string id in hwIds)
                            {
                                if (id != null && id.IndexOf("HID_DEVICE_UP:000D_U:0004", StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    isTouchUsage = true;
                                    break;
                                }
                            }
                        }

                        if (!isTouchUsage)
                        {
                            string[] compatIds = obj["CompatibleID"] as string[];
                            if (compatIds != null)
                            {
                                foreach (string id in compatIds)
                                {
                                    if (id != null && id.IndexOf("HID_DEVICE_UP:000D_U:0004", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        isTouchUsage = true;
                                        break;
                                    }
                                }
                            }
                        }

                        if (isTouchName || isTouchUsage)
                        {
                            TouchDeviceRecord rec = new TouchDeviceRecord
                            {
                                Name = name,
                                DeviceID = Convert.ToString(obj["DeviceID"] ?? ""),
                                Status = Convert.ToString(obj["Status"] ?? ""),
                                ConfigManagerErrorCode = obj["ConfigManagerErrorCode"] != null
                                    ? Convert.ToUInt32(obj["ConfigManagerErrorCode"])
                                    : 0u
                            };
                            allMatched.Add(rec);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                AppendUserLog("WARN", "WMI query warning: " + ex.Message);
            }

            List<string> pinnedIds = GetPinnedInstanceIds();
            if (pinnedIds.Count > 0)
            {
                List<TouchDeviceRecord> targetList = new List<TouchDeviceRecord>();
                foreach (string pin in pinnedIds)
                {
                    TouchDeviceRecord found = allMatched.Find(d => string.Equals(d.DeviceID, pin, StringComparison.OrdinalIgnoreCase));
                    if (found != null)
                    {
                        targetList.Add(found);
                    }
                    else
                    {
                        missingPins.Add(pin);
                    }
                }
                return targetList;
            }
            return allMatched;
        }

        private void RefreshDeviceStateAndLogs()
        {
            List<string> missingPins;
            List<TouchDeviceRecord> devices = QueryTouchDevices(out missingPins);
            List<string> configuredPins = GetPinnedInstanceIds();

            if (missingPins.Count > 0)
            {
                headerBanner.BackColor = Color.FromArgb(153, 27, 27);
                lblStatusTitle.Text = "[!] PINNED TOUCHSCREEN DISCONNECTED";
                lblStatusSubtitle.Text = "Admin-pinned device (" + string.Join("; ", missingPins.ToArray()) + ") is missing. Refusing to guess other devices.";
            }
            else if (devices.Count == 0)
            {
                headerBanner.BackColor = Color.FromArgb(153, 27, 27);
                lblStatusTitle.Text = "[!] TOUCHSCREEN DEVICE NOT FOUND";
                lblStatusSubtitle.Text = "No touchscreen (HID Usage 000D:0004) was detected in Device Manager. Check driver status or run Recovery.";
            }
            else if (devices.Count > 1 && configuredPins.Count == 0)
            {
                headerBanner.BackColor = Color.FromArgb(180, 83, 9);
                lblStatusTitle.Text = "[!] MULTIPLE TOUCHSCREENS FOUND (" + devices.Count + ") - ADMIN REQUIRED";
                lblStatusSubtitle.Text = "Safeguard active: Re-run Install-RobloxTouchSwitch.bat as Administrator to pin the touchscreen node(s).";
            }
            else
            {
                bool allCode22 = true;
                bool allOk = true;
                uint firstFaultCode = 0;
                string firstFaultStatus = "";
                List<string> idList = new List<string>();

                foreach (TouchDeviceRecord dev in devices)
                {
                    idList.Add(dev.DeviceID);
                    if (dev.ConfigManagerErrorCode != 22) allCode22 = false;
                    if (dev.ConfigManagerErrorCode != 0 || !string.Equals(dev.Status, "OK", StringComparison.OrdinalIgnoreCase))
                    {
                        allOk = false;
                        if (dev.ConfigManagerErrorCode != 22 && firstFaultCode == 0)
                        {
                            firstFaultCode = dev.ConfigManagerErrorCode;
                            firstFaultStatus = dev.Status;
                        }
                    }
                }

                string idSummary = string.Join("; ", idList.ToArray());

                if (allCode22)
                {
                    headerBanner.BackColor = Color.FromArgb(3, 105, 161);
                    lblStatusTitle.Text = "MOUSE MODE ACTIVE  (TOUCHSCREEN OFF)";
                    lblStatusSubtitle.Text = "Ready for Roblox (Fling Things and People). External mouse clicks & grabbing work normally. [" + idSummary + "]";
                }
                else if (allOk)
                {
                    headerBanner.BackColor = Color.FromArgb(21, 128, 61);
                    lblStatusTitle.Text = "TOUCHSCREEN ENABLED  (NORMAL HANDHELD MODE)";
                    lblStatusSubtitle.Text = "Touchscreen is ON and working normally. Click MOUSE MODE before playing Roblox with an external mouse. [" + idSummary + "]";
                }
                else
                {
                    headerBanner.BackColor = Color.FromArgb(180, 83, 9);
                    lblStatusTitle.Text = "[!] TOUCHSCREEN DRIVER ERROR (CODE " + firstFaultCode + ")";
                    lblStatusSubtitle.Text = "Device status is '" + firstFaultStatus + "' (Error Code " + firstFaultCode + "). Click RESTORE TOUCH or run Emergency Recovery. [" + idSummary + "]";
                }
            }

            LoadCombinedLogs();
        }

        private List<string> ReadTailLines(string filePath, int maxBytes, int maxLines)
        {
            List<string> result = new List<string>();
            if (!File.Exists(filePath)) return result;
            try
            {
                using (FileStream fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    long startPos = Math.Max(0, fs.Length - maxBytes);
                    fs.Seek(startPos, SeekOrigin.Begin);
                    using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                    {
                        if (startPos > 0) sr.ReadLine(); // discard partial first line
                        string line;
                        while ((line = sr.ReadLine()) != null)
                        {
                            if (!string.IsNullOrWhiteSpace(line)) result.Add(line);
                        }
                    }
                }
                if (result.Count > maxLines)
                {
                    result = result.GetRange(result.Count - maxLines, maxLines);
                }
            }
            catch { }
            return result;
        }

        private void LoadCombinedLogs()
        {
            try
            {
                List<string> combined = new List<string>();
                combined.AddRange(ReadTailLines(SystemLogPath, 32768, 50));
                combined.AddRange(ReadTailLines(UserLogPath, 32768, 30));
                combined.Sort(StringComparer.Ordinal);

                if (combined.Count > 0)
                {
                    int start = Math.Max(0, combined.Count - 70);
                    StringBuilder sb = new StringBuilder();
                    for (int i = start; i < combined.Count; i++)
                    {
                        sb.AppendLine(combined[i]);
                    }
                    txtLogViewer.Text = sb.ToString();
                    txtLogViewer.SelectionStart = txtLogViewer.Text.Length;
                    txtLogViewer.ScrollToCaret();
                }
                else
                {
                    txtLogViewer.Text = "Audit & GUI logs initialized. Click MOUSE MODE or RESTORE TOUCH to record events.";
                }
            }
            catch (Exception ex)
            {
                txtLogViewer.Text = "Unable to read logs: " + ex.Message;
            }
        }

        private async Task TriggerScheduledTaskAsync(string taskFullName, string friendlyActionName)
        {
            if (isBusy) return;

            List<string> missingPins;
            List<TouchDeviceRecord> preCheck = QueryTouchDevices(out missingPins);
            List<string> configuredPins = GetPinnedInstanceIds();

            if (missingPins.Count > 0)
            {
                string missStr = string.Join("; ", missingPins.ToArray());
                AppendUserLog("ERROR", "Safeguard halted '" + friendlyActionName + "': Pinned touchscreen '" + missStr + "' is missing.");
                RefreshDeviceStateAndLogs();
                MessageBox.Show(
                    "PINNED DEVICE MISSING:\r\n\r\n" +
                    "The Administrator pinned touchscreen device:\r\n" + missStr + "\r\n\r\n" +
                    "However, this device is not currently connected. To protect external monitors or other HID devices, Roblox Touchscreen Switch will never fall back to guessing.\r\n\r\n" +
                    "Reconnect the device or ask an Administrator to re-run Install-RobloxTouchSwitch.bat.",
                    "Pinned Touchscreen Not Found",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            if (preCheck.Count == 0)
            {
                AppendUserLog("ERROR", "Attempted '" + friendlyActionName + "', but no touchscreen device (HID 000D:0004) was found in Device Manager.");
                RefreshDeviceStateAndLogs();
                MessageBox.Show(
                    "The touchscreen device could not be found in Windows Device Manager.\r\n\r\n" +
                    "What to check:\r\n" +
                    "1. Ensure the handheld screen is powered on.\r\n" +
                    "2. Ask an Administrator to open Device Manager -> View -> Show hidden devices -> Human Interface Devices.\r\n" +
                    "3. Run 'Scan for hardware changes' or run Emergency-Restore-Touchscreen.bat.",
                    "Touchscreen Device Not Found",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return;
            }

            if (preCheck.Count > 1 && configuredPins.Count == 0)
            {
                StringBuilder ids = new StringBuilder();
                foreach (var d in preCheck) ids.AppendLine(" - " + d.DeviceID + " (Status: " + d.Status + ", Code: " + d.ConfigManagerErrorCode + ")");
                AppendUserLog("ERROR", "Safeguard halted '" + friendlyActionName + "': Multiple (" + preCheck.Count + ") unpinned touchscreen devices found.");
                RefreshDeviceStateAndLogs();
                MessageBox.Show(
                    "SAFETY STOP: Multiple (" + preCheck.Count + ") touchscreen devices were detected:\r\n\r\n" +
                    ids.ToString() + "\r\n" +
                    "To protect your system, Roblox Touchscreen Switch will never guess which HID devices to disable.\r\n\r\n" +
                    "Please ask the Administrator to re-run Install-RobloxTouchSwitch.bat to pin the touchscreen InstanceId(s) in config.json.",
                    "Administrator Intervention Required",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            isBusy = true;
            btnMouseMode.Enabled = false;
            btnRestoreTouch.Enabled = false;
            lblStatusTitle.Text = "APPLYING " + friendlyActionName.ToUpperInvariant() + "...";
            lblStatusSubtitle.Text = "Triggering restricted SYSTEM Scheduled Task (" + taskFullName + ")...";
            AppendUserLog("INFO", "Requesting Scheduled Task '" + taskFullName + "' for '" + friendlyActionName + "'.");

            WorkerStatusReport beforeReport = ReadStatusReport();
            long previousTimestampUtc = beforeReport != null ? beforeReport.TimestampUtc : 0L;

            try
            {
                int exitCode = await Task.Run(() =>
                {
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = Path.Combine(Environment.SystemDirectory, "schtasks.exe"),
                        Arguments = "/Run /TN \"" + taskFullName + "\"",
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    };
                    using (Process p = Process.Start(psi))
                    {
                        bool finished = p.WaitForExit(8000);
                        if (!finished)
                        {
                            try { p.Kill(); } catch { }
                            return -999;
                        }
                        return p.ExitCode;
                    }
                });

                if (exitCode == -999)
                {
                    AppendUserLog("ERROR", "schtasks.exe /Run timed out after 8 seconds for '" + taskFullName + "'.");
                    MessageBox.Show("Timed out waiting for Scheduled Task '" + taskFullName + "' to start.", "Scheduled Task Timeout", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                else if (exitCode != 0)
                {
                    AppendUserLog("ERROR", "schtasks.exe /Run failed for '" + taskFullName + "' with exit code " + exitCode + ".");
                    MessageBox.Show(
                        "Could not trigger Scheduled Task '" + taskFullName + "' (Exit Code " + exitCode + ").\r\n\r\n" +
                        "Please ask an Administrator to run 'Install-RobloxTouchSwitch.bat' to register and grant permissions for the tasks.",
                        "Scheduled Task Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                else
                {
                    WorkerStatusReport updatedReport = null;
                    for (int attempt = 1; attempt <= 40; attempt++)
                    {
                        double elapsedSec = Math.Round(attempt * 0.3, 1);
                        lblStatusSubtitle.Text = "Waiting for SYSTEM hardware completion (" + elapsedSec.ToString("0.0") + "s / 12.0s)...";
                        await Task.Delay(300);
                        WorkerStatusReport candidate = ReadStatusReport();
                        if (candidate != null && candidate.TimestampUtc > previousTimestampUtc)
                        {
                            updatedReport = candidate;
                            break;
                        }
                    }

                    if (updatedReport == null)
                    {
                        AppendUserLog("WARN", "SYSTEM worker timed out (did not update status.json within 12.0 seconds) for '" + taskFullName + "'.");
                        headerBanner.BackColor = Color.FromArgb(180, 83, 9);
                        lblStatusTitle.Text = "[!] WORKER TIMEOUT - CHECK SYSTEM LOG";
                        lblStatusSubtitle.Text = "Scheduled Task launched, but the SYSTEM worker did not report back within 12 seconds.";
                        MessageBox.Show(
                            "WORKER TIMEOUT (Not a confirmed hardware failure):\r\n\r\n" +
                            "Task Scheduler accepted '" + taskFullName + "', but the background SYSTEM worker did not finish updating status.json within 12.0 seconds.\r\n\r\n" +
                            "Click 'Refresh Status' in a few seconds, or click 'Open SYSTEM Audit Log' to inspect progress.",
                            "Worker Response Timeout",
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Warning);
                    }
                    else if (!string.Equals(updatedReport.ResultCode, "SUCCESS", StringComparison.OrdinalIgnoreCase))
                    {
                        AppendUserLog("ERROR", "SYSTEM worker reported " + updatedReport.ResultCode + ": " + updatedReport.Message);
                        MessageBox.Show(
                            "The SYSTEM worker reported an issue (" + updatedReport.ResultCode + "):\r\n\r\n" +
                            updatedReport.Message,
                            "Roblox Touchscreen Switch - Hardware Alert",
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Warning);
                    }
                    else
                    {
                        AppendUserLog("INFO", "SYSTEM worker confirmed " + updatedReport.TouchState + " for " + updatedReport.InstanceId + ".");
                    }
                }
            }
            catch (Exception ex)
            {
                AppendUserLog("ERROR", "Exception running scheduled task: " + ex.Message);
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
