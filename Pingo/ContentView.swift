import SwiftUI
import Combine
import UserNotifications

// --- 1. 数据模型 ---
struct StudentStatus: Identifiable, Codable {
    var id: String { name }
    let name: String
    let lastCheckin: String
    let config: ConfigData
    
    struct ConfigData: Codable {
        let interval: String?
        let reminderTime: String?
    }

    var lastDate: Date {
        let ts = Double(lastCheckin) ?? 0
        return Date(timeIntervalSince1970: ts / 1000)
    }
}

// --- 2. 主界面 ---
struct ContentView: View {
    @AppStorage("hasCompletedSetup") var hasCompletedSetup = false
    @AppStorage("savedUserName") var userName = ""
    @AppStorage("familyEmail") var familyEmail = ""
    @AppStorage("userRole") var userRole = "student"
    @AppStorage("alertInterval") var alertInterval: Int = 24
    @AppStorage("adminPassword") var adminPassword = ""
    @AppStorage("studentReminderTime") var studentReminderTime = Date()
    @AppStorage("advanceNoticeMinutes") var advanceNoticeMinutes: Int = 30
    
    @State private var isShowingSettings = false
    @State private var isShowingPasswordLock = false
    @State private var isShowingResetFlow = false
    @State private var inputPassword = ""
    @State private var isAnimating = false
    
    @State private var resetCodeInput = ""
    @State private var serverSentCode = ""
    @State private var isCodeVerified = false
    @State private var newPasswordInput = ""
    
    @State private var students: [StudentStatus] = []
    @State private var statusMessage = "安全连接中..."
    @State private var lastCheckinDate: Date? = nil
    @State private var timeRemaining: String = "同步中"
    @State private var currentTime = Date()

    let baseURL = "https://pingo.jianyuan-cao.workers.dev"
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(UIColor.systemBackground), Color(UIColor.secondarySystemBackground)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            if !hasCompletedSetup {
                welcomeView
            } else {
                mainAppView
            }
        }
        .sheet(isPresented: $isShowingResetFlow) { resetSheetView }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(name: $userName, email: $familyEmail, interval: $alertInterval, pwd: $adminPassword, reminderTime: $studentReminderTime, advanceNotice: $advanceNoticeMinutes, userRole: $userRole, baseURL: baseURL, onComplete: {
                fetchStatus() // 保存后立即同步一次
            })
        }
        .alert("管理身份验证", isPresented: $isShowingPasswordLock) {
            SecureField("输入4位管理密码", text: $inputPassword)
                .keyboardType(.numberPad)
            Button("确定") {
                if inputPassword == adminPassword {
                    isShowingSettings = true
                } else {
                    showTempMessage("❌ 密码认证失败")
                }
                inputPassword = ""
            }
            Button("忘记密码", role: .destructive) { triggerResetAPI() }
            Button("取消", role: .cancel) { inputPassword = "" }
        }
        .onAppear {
            if hasCompletedSetup { fetchStatus() }
            requestNotificationPermission()
        }
        .onReceive(timer) { input in
            self.currentTime = input
            if hasCompletedSetup {
                updateCountdown()
                let seconds = Int(input.timeIntervalSince1970) % 60
                // 每10秒自动从云端拉取一次最新配置，实现静默同步
                if seconds % 10 == 0 { fetchStatus() }
            }
        }
    }

    var mainAppView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pingo").font(.title2.bold()).foregroundColor(.green)
                Spacer()
                Button(action: {
                    if userRole == "parent" { isShowingPasswordLock = true }
                    else { isShowingSettings = true }
                }) {
                    Image(systemName: "gearshape.fill").foregroundColor(.secondary)
                }
            }
            .padding().background(.ultraThinMaterial)

            if userRole == "parent" {
                parentSection
            } else {
                studentSection
            }
        }
    }

    // --- 4. 绿色声波纹学生端 ---
    var studentSection: some View {
        VStack(spacing: 30) {
            Spacer()
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("你好，\(userName)").font(.largeTitle.bold())
                    Button(action: {
                        self.lastCheckinDate = nil
                        self.timeRemaining = "同步中..."
                        fetchStatus()
                        showTempMessage("🔄 配置与倒计时已重置")
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
                Text(statusMessage).font(.subheadline)
                    .foregroundColor(statusMessage.contains("❌") ? .red : .secondary)
            }

            Text(timeRemaining)
                .font(.system(size: 54, weight: .bold, design: .monospaced))
                .foregroundColor(timeRemaining.contains("⚠️") ? .red : .primary)

            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .scaleEffect(isAnimating ? 1.6 : 1.0)
                        .opacity(isAnimating ? 0 : 0.8)
                        .animation(
                            isAnimating ?
                            Animation.easeOut(duration: 2.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.6) : .default,
                            value: isAnimating
                        )
                }
                
                Button(action: triggerCheckin) {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(
                            RadialGradient(colors: [Color.white.opacity(0.8), Color.green.opacity(0.4)], center: .topLeading, startRadius: 10, endRadius: 150)
                        )
                        .overlay(Circle().stroke(Color.green.opacity(0.3), lineWidth: 1))
                        .shadow(color: Color.green.opacity(0.2), radius: 15, x: 10, y: 10)
                        
                        VStack(spacing: 5) {
                            Image(systemName: "checkmark.shield.fill").font(.system(size: 45))
                            Text("报平安").font(.headline.bold())
                        }
                        .foregroundColor(.green)
                    }
                    .frame(width: 180, height: 180)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(width: 250, height: 250)
            .task {
                isAnimating = true
            }
            
            VStack(spacing: 4) {
                Text("安全监控周期: \(alertInterval) 小时")
                Text("提前 \(advanceNoticeMinutes) 分钟通知我")
            }
            .font(.caption).foregroundColor(.secondary)
            
            Spacer()
        }
    }

    // --- 5. 动态实时家长端 ---
    var parentSection: some View {
        List {
            Section(header: Text("全家实时状态 (每秒更新)")) {
                if students.isEmpty { Text("正在同步云端数据...").foregroundColor(.secondary) }
                ForEach(students) { student in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(student.name).font(.headline)
                            Text("上次报备: \(formatDate(student.lastDate))").font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(getCountdownFor(student, current: currentTime))
                            .font(.system(.body, design: .monospaced)).bold()
                            .foregroundColor(getCountdownFor(student, current: currentTime).contains("⚠️") ? .red : .green)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            Section {
                Button(action: fetchStatus) {
                    Label("强制刷新云端", systemImage: "arrow.clockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // --- 6. 核心逻辑 (修复同步与通知调度) ---
    func fetchStatus() {
        guard !familyEmail.isEmpty else { return }
        var components = URLComponents(string: "\(baseURL)/status")!
        components.queryItems = [URLQueryItem(name: "email", value: familyEmail)]
        URLSession.shared.dataTask(with: components.url!) { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stData = json["students"] as? [[String: Any]] else { return }
            
            if let remotePwd = json["adminPassword"] as? String {
                DispatchQueue.main.async { self.adminPassword = remotePwd }
            }
            
            let decoded = stData.compactMap { dict -> StudentStatus? in
                guard let name = dict["name"] as? String, let lc = dict["lastCheckin"] as? String, let cfg = dict["config"] as? [String: Any] else { return nil }
                return StudentStatus(name: name, lastCheckin: lc, config: StudentStatus.ConfigData(interval: cfg["interval"] as? String, reminderTime: cfg["reminderTime"] as? String))
            }
            
            DispatchQueue.main.async {
                self.students = decoded
                // 查找当前用户的配置
                if let me = decoded.first(where: { $0.name == userName }) {
                    self.lastCheckinDate = me.lastDate
                    if let inv = me.config.interval, let invInt = Int(inv) {
                        if self.alertInterval != invInt {
                            self.alertInterval = invInt
                        }
                    }
                } else if userRole == "student" {
                    for s in decoded {
                         if let inv = s.config.interval, let invInt = Int(inv) {
                             self.alertInterval = invInt
                             break
                         }
                    }
                }
                self.updateCountdown()
                // 配置同步后，重新调度通知
                if self.userRole == "student" {
                    self.scheduleLocalNotification()
                }
            }
        }.resume()
    }

    func showTempMessage(_ msg: String) {
        self.statusMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.statusMessage = "正常在线" }
    }

    func updateCountdown() {
        guard let last = lastCheckinDate else { return }
        let diff = last.addingTimeInterval(Double(alertInterval) * 3600).timeIntervalSince(Date())
        if diff <= 0 {
            if timeRemaining != "⚠️ 已超时" { timeRemaining = "⚠️ 已超时" }
        } else {
            let h = Int(diff) / 3600, m = (Int(diff) % 3600) / 60, s = Int(diff) % 60
            let newStr = String(format: "%02d:%02d:%02d", h, m, s)
            if timeRemaining != newStr { timeRemaining = newStr }
        }
    }

    func getCountdownFor(_ student: StudentStatus, current: Date) -> String {
        let inv = Double(student.config.interval ?? "24") ?? 24
        let diff = student.lastDate.addingTimeInterval(inv * 3600).timeIntervalSince(current)
        if diff <= 0 { return "⚠️ 已超时" }
        let h = Int(diff) / 3600, m = (Int(diff) % 3600) / 60, s = Int(diff) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    func triggerCheckin() {
        showTempMessage("☁️ 同步中...")
        var components = URLComponents(string: "\(baseURL)/checkin")!
        components.queryItems = [URLQueryItem(name: "email", value: familyEmail), URLQueryItem(name: "name", value: userName)]
        URLSession.shared.dataTask(with: components.url!) { _, _, _ in
            DispatchQueue.main.async {
                showTempMessage("✅ 报平安成功")
                fetchStatus()
            }
        }.resume()
    }

    // --- 核心修复：本地通知调度函数 ---
    func scheduleLocalNotification() {
        guard userRole == "student", let last = lastCheckinDate else { return }
        
        // 1. 移除旧的待发通知
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // 2. 计算通知时间点 = 上次打卡时间 + 周期秒数 - 提前通知秒数
        let totalIntervalSeconds = Double(alertInterval) * 3600
        let advanceSeconds = Double(advanceNoticeMinutes) * 60
        let triggerTime = last.addingTimeInterval(totalIntervalSeconds - advanceSeconds)
        
        let timeToWait = triggerTime.timeIntervalSince(Date())
        
        // 如果计算出来的时间已经在过去，就不设置通知
        guard timeToWait > 0 else { return }
        
        // 3. 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "Pingo 安全提醒"
        content.body = "距离预定的报平安时间还有 \(advanceNoticeMinutes) 分钟，请及时打卡。"
        content.sound = .default
        
        // 4. 创建触发器
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeToWait, repeats: false)
        
        // 5. 提交
        let request = UNNotificationRequest(identifier: "PingoReminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func triggerResetAPI() {
        self.isShowingResetFlow = true
        var components = URLComponents(string: "\(baseURL)/reset")!
        components.queryItems = [URLQueryItem(name: "email", value: familyEmail)]
        URLSession.shared.dataTask(with: components.url!) { data, _, _ in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let code = json["debug_sent_code"] {
                DispatchQueue.main.async { self.serverSentCode = "\(code)" }
            }
        }.resume()
    }

    func checkCodeMatch() { if resetCodeInput == serverSentCode { withAnimation { isCodeVerified = true } } }
    
    func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "--" }
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: date)
    }

    // --- 7. 视图组件 ---
    var welcomeView: some View {
        VStack(spacing: 40) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 80)).foregroundColor(.green)
            Text("Pingo 守护").font(.largeTitle.bold())
            VStack(spacing: 15) {
                Button(action: { userRole = "parent"; isShowingSettings = true }) {
                    Label("我是家长", systemImage: "person.2.fill")
                        .frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(15)
                }
                Button(action: { userRole = "student"; isShowingSettings = true }) {
                    Label("我是学生", systemImage: "person.fill")
                        .frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(15)
                }
            }.padding(.horizontal, 40)
        }
    }

    var resetSheetView: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                VStack(spacing: 30) {
                    if !isCodeVerified {
                        Text("重置管理密码").font(.title2.bold())
                        Text("请输入邮箱收到的 6 位验证码").font(.subheadline).foregroundColor(.secondary)
                        TextField("000000", text: $resetCodeInput)
                            .keyboardType(.numberPad)
                            .font(.system(size: 45, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        Button(action: checkCodeMatch) {
                            Text("验证码校验").frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(12)
                        }
                    } else {
                        Text("验证成功").font(.title2.bold()).foregroundColor(.green)
                        Text("请设置新的 4 位管理密码").font(.subheadline).foregroundColor(.secondary)
                        SecureField("新密码", text: $newPasswordInput)
                            .keyboardType(.numberPad)
                            .font(.system(size: 45, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        Button(action: {
                            if newPasswordInput.count == 4 {
                                adminPassword = newPasswordInput
                                updateRemotePassword(newPasswordInput)
                                isShowingResetFlow = false
                            }
                        }) {
                            Text("保存并退出").frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(12)
                        }
                    }
                    Spacer()
                }
                .padding(30)
            }
            .navigationBarItems(trailing: Button("取消") { isShowingResetFlow = false })
        }
    }
    
    func updateRemotePassword(_ newPwd: String) {
        var components = URLComponents(string: "\(baseURL)/saveconfig")!
        components.queryItems = [
            URLQueryItem(name: "email", value: familyEmail),
            URLQueryItem(name: "name", value: "Admin"),
            URLQueryItem(name: "pwd", value: newPwd)
        ]
        URLSession.shared.dataTask(with: components.url!).resume()
    }
}

// --- 8. 设置视图 ---
struct SettingsView: View {
    @Binding var name: String
    @Binding var email: String
    @Binding var interval: Int
    @Binding var pwd: String
    @Binding var reminderTime: Date
    @Binding var advanceNotice: Int
    @Binding var userRole: String
    @AppStorage("hasCompletedSetup") var hasCompletedSetup = false
    @Environment(\.dismiss) var dismiss
    let baseURL: String
    var onComplete: () -> Void

    var body: some View {
        NavigationView {
            Form {
                if userRole == "parent" {
                    Section(header: Text("账号设置")) {
                        TextField("联系邮箱", text: $email).autocapitalization(.none).keyboardType(.emailAddress)
                        SecureField("4位管理密码", text: $pwd).keyboardType(.numberPad)
                    }
                    Section(header: Text("全家监控策略")) {
                        Stepper("报警周期: \(interval) 小时", value: $interval, in: 1...72)
                    }
                } else {
                    Section(header: Text("身份设置")) {
                        TextField("学生姓名", text: $name)
                        TextField("家长邮箱", text: $email).autocapitalization(.none).keyboardType(.emailAddress)
                    }
                    Section(header: Text("通知设置")) {
                        Stepper("提前提醒: \(advanceNotice) 分钟", value: $advanceNotice, in: 5...120, step: 5)
                    }
                }

                Button("完成并保存") {
                    saveAndUpload()
                }.disabled(email.isEmpty || (userRole == "parent" && pwd.count != 4) || (userRole == "student" && name.isEmpty))
            }
            .navigationTitle("配置 Pingo")
        }
    }

    func saveAndUpload() {
        hasCompletedSetup = true
        var components = URLComponents(string: "\(baseURL)/saveconfig")!
        let uploadName = userRole == "parent" ? "Admin" : name
        
        var items = [
            URLQueryItem(name: "email", value: email),
            URLQueryItem(name: "name", value: uploadName),
            URLQueryItem(name: "interval", value: "\(interval)"),
            URLQueryItem(name: "reminderTime", value: reminderTime.description)
        ]
        if userRole == "parent" { items.append(URLQueryItem(name: "pwd", value: pwd)) }
        components.queryItems = items
        
        URLSession.shared.dataTask(with: components.url!) { _, _, _ in
            DispatchQueue.main.async {
                onComplete()
            }
        }.resume()
        dismiss()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
