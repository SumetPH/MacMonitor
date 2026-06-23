import SwiftUI
import CoreGraphics

public struct SettingsWindowView: View {
    @ObservedObject private var manager = DisplayManager.shared
    @ObservedObject private var presetStore = DisplayPresetStore.shared
    
    @State private var selectedDisplayID: CGDirectDisplayID? = nil
    @State private var activeTab = "displays"
    
    // Preset Creation State
    @State private var newPresetName = ""
    
    // Experimental Custom Override state
    @State private var customWidth = 1920
    @State private var customHeight = 1080
    @State private var experimentalEnabled = false
    @State private var hotReloadHiDPI = true
    
    // Notification & Alert states
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingUninstallReport = false
    @State private var uninstallReportText = ""
    
    public init() {}
    
    private var selectedDisplay: DisplayInfo? {
        if let id = selectedDisplayID {
            return manager.displays.first(where: { $0.displayID == id })
        }
        return manager.displays.first
    }
    
    private func rotationFailureMessage(for displayID: CGDirectDisplayID) -> String {
        let log = DiagnosticsService.shared.getLogs().reversed().first {
            $0.displayID == displayID && $0.operationType == "rotate"
        }
        
        var message = "ไม่สามารถหมุนหน้าจอนี้ได้ หน้าจอเชื่อมต่ออาจไม่สนับสนุนฟังก์ชันนี้ หรือ macOS ปฏิเสธ private rotation API"
        if let log {
            message += "\n\nรายละเอียด: \(log.details)"
            if let errorDescription = log.errorDescription, !errorDescription.isEmpty {
                message += "\n\(errorDescription)"
            }
        }
        message += "\n\nลองเทียบกับการหมุนผ่าน macOS System Settings โดยตรงอีกครั้งเพื่อแยกว่าเป็นข้อจำกัดของจอ/ระบบ หรือเป็น API ที่แอปเรียกไม่ได้"
        return message
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 6) {
                sidebarButton(title: "จอภาพ (Displays)", icon: "desktopcomputer", tab: "displays")
                sidebarButton(title: "ค่าที่ตั้งไว้ (Presets)", icon: "slider.horizontal.3", tab: "presets")
                sidebarButton(title: "การทดลอง (Experimental)", icon: "flask.fill", tab: "experimental")
                sidebarButton(title: "การวินิจฉัย (Diagnostics)", icon: "doc.text.magnifyingglass", tab: "diagnostics")
                
                Spacer()
                
                // Active Display Info Summary in Sidebar
                if let display = selectedDisplay {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.name)
                            .font(.caption)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        Text("\(display.currentWidth)x\(display.currentHeight) @ \(Int(display.refreshRate))Hz")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.horizontal, 4)
                }
            }
            .frame(width: 170)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.15))
            
            Divider()
            
            // Tab Contents
            Group {
                switch activeTab {
                case "displays":
                    displaysTab()
                case "presets":
                    presetsTab()
                case "experimental":
                    experimentalTab()
                case "diagnostics":
                    DiagnosticsView()
                default:
                    displaysTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 500)
        .onAppear {
            if selectedDisplayID == nil, let first = manager.displays.first {
                selectedDisplayID = first.displayID
            }
            experimentalEnabled = ExperimentalDisplayService.shared.isExperimentalModeEnabled
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Mac Monitor"), message: Text(alertMessage), dismissButton: .default(Text("ตกลง")))
        }
        .sheet(isPresented: $showingUninstallReport) {
            VStack(spacing: 16) {
                Text("รายงานการถอนการติดตั้งสำเร็จ")
                    .font(.headline)
                ScrollView {
                    Text(uninstallReportText)
                        .font(.system(.footnote, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(6)
                }
                .frame(width: 500, height: 300)
                
                Button("ปิด (Close)") {
                    showingUninstallReport = false
                    // Quit application after uninstall
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        // Overlay for Resolution Rollback Confirmation
        .overlay {
            if manager.showConfirmationDialog, manager.activeConfirmationDisplayID != nil {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Text("ยืนยันการเปลี่ยนความละเอียดหน้าจอ?")
                        .font(.headline)
                    Text("ระบบจะคืนค่าเดิมอัตโนมัติภายใน 15 วินาทีหากไม่มีการยืนยัน เพื่อป้องกันหน้าจอไม่สามารถแสดงผลได้")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        Button("คืนค่าเดิม (Revert)") {
                            manager.revertMode()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("ยืนยันใช้งาน (Confirm)") {
                            manager.confirmMode()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 380)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 8)
            }
        }
    }
    
    // MARK: - Sidebar Button Helper
    private func sidebarButton(title: String, icon: String, tab: String) -> some View {
        Button(action: { activeTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(activeTab == tab ? .white : .primary)
            .background(activeTab == tab ? Color.accentColor : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    // MARK: - Displays Tab View
    private func displaysTab() -> some View {
        VStack(spacing: 16) {
            // Display Selector
            HStack {
                Text("เลือกจอภาพ:")
                    .font(.body)
                Picker("", selection: $selectedDisplayID) {
                    ForEach(manager.displays) { display in
                        Text(display.name).tag(Optional(display.displayID))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 280)
                .onChange(of: selectedDisplayID) { _, _ in
                    manager.refreshDisplays()
                }
                
                Spacer()
                
                Button(action: {
                    _ = DisplayPowerService.shared.resetDisplayConnections()
                    manager.refreshDisplays()
                }) {
                    Image(systemName: "display.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("รีเซ็ตและเชื่อมต่อจอที่ถูกปิดกลับมา")
                
                Button(action: { manager.refreshDisplays() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("รีเฟรชรายชื่อจอภาพ")
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            if let display = selectedDisplay {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Display Power Control
                        HStack {
                            Text("สถานะการเปิด/ปิดจอภาพ:")
                                .fontWeight(.semibold)
                            Spacer()
                            
                            let isDisabled = display.isAppDisconnected || DisplayPowerService.shared.isDisplayDisabled(display.displayID)
                            
                            Button(action: {
                                if isDisabled {
                                    DisplayPowerService.shared.enableDisplay(displayID: display.displayID)
                                    manager.refreshDisplays()
                                } else {
                                    // Warn before disabling
                                    let alert = NSAlert()
                                    alert.messageText = "คำเตือนสำหรับการปิดจอภาพ"
                                    alert.informativeText = "คุณแน่ใจหรือไม่ว่าต้องการตัดการทำงานของจอภาพนี้? หน้าจออาจกะพริบและจัดวางตำแหน่งหน้าต่างใหม่"
                                    alert.addButton(withTitle: "ยืนยันปิดจอ")
                                    alert.addButton(withTitle: "ยกเลิก")
                                    let res = alert.runModal()
                                    if res == .alertFirstButtonReturn {
                                        DisplayPowerService.shared.disableDisplay(displayID: display.displayID)
                                        manager.refreshDisplays()
                                    }
                                }
                            }) {
                                Text(isDisabled ? "เปิดใช้งานจอ (Enable)" : "ปิดใช้งานจอ (Disable)")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!isDisabled && display.isMain) // Prevent disabling the primary/main screen
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                        
                        if display.isAppDisconnected {
                            Text("จอนี้ถูกปิดการเชื่อมต่อจาก layout ของ macOS แล้ว กด Enable เพื่อเชื่อมต่อกลับ")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                        // Resolution Selection
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ความละเอียดและโหมดการแสดงผล (Resolution Mode)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            
                            let grouped = RefreshRateService.shared.groupModesByResolution(
                                DisplayModeService.shared.getAvailableModes(for: display.displayID)
                            )
                            
                            List {
                                ForEach(grouped) { group in
                                    HStack {
                                        Text("\(group.width) x \(group.height)")
                                            .fontWeight(.semibold)
                                        if group.isHiDPI {
                                            Text("HiDPI")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.2))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        }
                                        Spacer()
                                        
                                        // Pick refresh rates inside this group
                                        Menu {
                                            ForEach(group.refreshRates, id: \.self) { rate in
                                                Button("\(Int(rate)) Hz") {
                                                    manager.changeMode(
                                                        displayID: display.displayID,
                                                        width: group.width,
                                                        height: group.height,
                                                        refreshRate: rate,
                                                        isHiDPI: group.isHiDPI
                                                    )
                                                }
                                            }
                                        } label: {
                                            let currentMatch = display.currentWidth == group.width &&
                                                               display.currentHeight == group.height &&
                                                               display.isHiDPI == group.isHiDPI
                                            
                                            Text(currentMatch ? "\(Int(display.refreshRate)) Hz (กำลังใช้งาน)" : "เลือกเฟรมเรต")
                                                .foregroundColor(currentMatch ? .accentColor : .primary)
                                        }
                                        .frame(width: 140)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .frame(height: 160)
                            .cornerRadius(6)
                        }
                        
                        // Rotation Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("การหมุนหน้าจอ (Display Rotation)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            
                            let canRotate = RotationService.shared.canRotate(displayID: display.displayID)
                            
                            HStack(spacing: 12) {
                                ForEach([0, 90, 180, 270], id: \.self) { angle in
                                    if display.rotation == angle {
                                        Button("\(angle)°") {
                                            let success = RotationService.shared.rotate(displayID: display.displayID, to: angle)
                                            if success {
                                                manager.refreshDisplays()
                                            } else {
                                                alertMessage = rotationFailureMessage(for: display.displayID)
                                                showingAlert = true
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(!canRotate)
                                    } else {
                                        Button("\(angle)°") {
                                            let success = RotationService.shared.rotate(displayID: display.displayID, to: angle)
                                            if success {
                                                manager.refreshDisplays()
                                            } else {
                                                alertMessage = rotationFailureMessage(for: display.displayID)
                                                showingAlert = true
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(!canRotate)
                                    }
                                }
                            }
                            
                            if !canRotate {
                                Text("หน้าจอแสดงผลนี้ไม่รองรับการปรับหมุนหน้าจอผ่านแอปพลิเคชัน (โปรดตรวจสอบหรือเปลี่ยนการตั้งค่าผ่าน System Settings ของ macOS แทน)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        
                        // DDC/CI Brightness Control
                        if DDCService.shared.supportsDDC(displayID: display.displayID) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ควบคุมความสว่างผ่าน DDC/CI & Native API")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                
                                HStack {
                                    Image(systemName: "sun.max.fill")
                                    
                                    let currentBr = DDCService.shared.readBrightness(displayID: display.displayID) ?? 0.8
                                    
                                    Slider(value: Binding(
                                        get: { currentBr },
                                        set: { DDCService.shared.writeBrightness(displayID: display.displayID, value: $0) }
                                    ), in: 0.0...1.0)
                                    
                                    Text("\(Int(currentBr * 100))%")
                                        .frame(width: 45, alignment: .trailing)
                                }
                            }
                            .padding(.top, 4)
                        }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            } else {
                Spacer()
                Text("ไม่พบหน้าจอเชื่อมต่อที่ทำงานอยู่")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
    
    // MARK: - Presets Tab View
    private func presetsTab() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("การจัดการ Presets หน้าจอ")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 16)
                .padding(.horizontal)
            
            // Create preset form
            if let display = selectedDisplay {
                VStack(alignment: .leading, spacing: 10) {
                    Text("บันทึกการตั้งค่าปัจจุบันของ \(display.name) เป็น Preset:")
                        .font(.body)
                    
                    HStack {
                        TextField("ตั้งชื่อ Preset เช่น โหมดทำงาน, โหมดเกม...", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("บันทึก Preset") {
                            guard !newPresetName.isEmpty else { return }
                            let currentBr = DDCService.shared.readBrightness(displayID: display.displayID)
                            let preset = DisplayPreset(
                                name: newPresetName,
                                displayUUID: display.identifier.uuid,
                                displayVendorID: display.identifier.vendorID,
                                displayProductID: display.identifier.productID,
                                displaySerialNumber: display.identifier.serialNumber,
                                width: display.currentWidth,
                                height: display.currentHeight,
                                pixelWidth: display.currentPixelWidth,
                                pixelHeight: display.currentPixelHeight,
                                refreshRate: display.refreshRate,
                                isHiDPI: display.isHiDPI,
                                rotation: display.rotation,
                                brightness: currentBr
                            )
                            presetStore.savePreset(preset)
                            newPresetName = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPresetName.isEmpty)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // List Presets
            if presetStore.presets.isEmpty {
                Spacer()
                Text("ยังไม่มีการสร้าง Preset ค่าจอภาพล่วงหน้า")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List {
                    ForEach(presetStore.presets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                    .fontWeight(.bold)
                                Text("ขนาด: \(preset.width)x\(preset.height) @ \(Int(preset.refreshRate))Hz | หมุน \(preset.rotation)° \(preset.isHiDPI ? "(HiDPI)" : "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            // Auto Apply toggle
                            Toggle("ใช้ค่าออโต้เมื่อเชื่อมต่อ", isOn: Binding(
                                get: { preset.autoApply },
                                set: { val in
                                    var updated = preset
                                    updated.autoApply = val
                                    presetStore.savePreset(updated)
                                }
                            ))
                            .font(.caption)
                            .toggleStyle(.checkbox)
                            .padding(.trailing, 8)
                            
                            Button("ใช้ค่าด่วน (Apply)") {
                                _ = presetStore.applyPreset(preset, availableDisplays: manager.displays)
                                manager.refreshDisplays()
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                presetStore.deletePreset(id: preset.id)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .cornerRadius(6)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Experimental Tab View
    private func experimentalTab() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("การตั้งค่าขั้นสูงและการทดลอง (Experimental)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.top, 16)
                
                Toggle("เปิดใช้งานฟังก์ชันทดลอง (Enable Experimental Features)", isOn: $experimentalEnabled)
                    .onChange(of: experimentalEnabled) { _, newValue in
                        ExperimentalDisplayService.shared.isExperimentalModeEnabled = newValue
                    }
                    .font(.headline)
                
                Text("คำเตือน: คุณลักษณะการทดลองอาจเรียกใช้ฟังก์ชัน Private API ของ macOS หรือเขียนไฟล์ overrides ระบบ ควรใช้งานด้วยความระมัดระวัง")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                
                if experimentalEnabled {
                    // Custom Override generation UI
                    VStack(alignment: .leading, spacing: 12) {
                        Text("การเพิ่มความละเอียดสเกล HiDPI แบบ Custom (Display Override Plist)")
                            .fontWeight(.bold)
                        
                        if let display = selectedDisplay {
                            Text("หน้าจอเป้าหมาย: \(display.name)")
                                .font(.caption)
                            Text("สถานะ HiDPI override ของจอนี้: \(HiDPIService.shared.isHiDPIOverrideEnabled(for: display) ? "เปิด" : "ปิด")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("ความกว้างตรรกะ (Logical Width):")
                                        .font(.caption)
                                    TextField("Width", value: $customWidth, formatter: NumberFormatter())
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("ความสูงตรรกะ (Logical Height):")
                                        .font(.caption)
                                    TextField("Height", value: $customHeight, formatter: NumberFormatter())
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            
                            Toggle("Hot reload หลังเปลี่ยนค่า (ไม่ต้อง restart เครื่อง)", isOn: $hotReloadHiDPI)
                                .toggleStyle(.checkbox)
                            
                            Toggle("เปิด HiDPI override สำหรับจอนี้", isOn: Binding(
                                get: { HiDPIService.shared.isHiDPIOverrideEnabled(for: display) },
                                set: { enabled in
                                    HiDPIService.shared.setHiDPIOverrideEnabled(
                                        enabled,
                                        for: display,
                                        customResolutions: [(width: customWidth, height: customHeight)],
                                        hotReload: hotReloadHiDPI
                                    ) { result in
                                        switch result {
                                        case .success(let message):
                                            alertMessage = "\(message)\n\(hotReloadHiDPI ? "รีโหลด config แล้ว หาก mode ยังไม่ขึ้นให้กด Refresh หรือถอด/เสียบจอใหม่" : "ปิด Hot reload อยู่ หาก mode ยังไม่ขึ้นอาจต้อง reconnect/restart")"
                                            showingAlert = true
                                            manager.refreshDisplays()
                                        case .failure(let err):
                                            alertMessage = "ไม่สามารถเปลี่ยน HiDPI override ได้: \(err.localizedDescription)"
                                            showingAlert = true
                                        }
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .disabled(display.isAppDisconnected)
                            
                            Button("เขียน override ซ้ำและรีโหลดตอนนี้") {
                                HiDPIService.shared.setHiDPIOverrideEnabled(
                                    true,
                                    for: display,
                                    customResolutions: [(width: customWidth, height: customHeight)],
                                    hotReload: hotReloadHiDPI
                                ) { result in
                                    switch result {
                                    case .success(let message):
                                        alertMessage = "\(message)\n\(hotReloadHiDPI ? "รีโหลด config แล้ว" : "เขียนไฟล์แล้ว แต่ยังไม่ได้ reload")"
                                        showingAlert = true
                                        manager.refreshDisplays()
                                    case .failure(let err):
                                        alertMessage = "ไม่สามารถสร้างไฟล์ตั้งค่าได้: \(err.localizedDescription)"
                                        showingAlert = true
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(display.isAppDisconnected)
                        } else {
                            Text("ไม่มีหน้าจอเชื่อมต่อที่รองรับการเขียนไฟล์ overrides")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
                
                Divider()
                
                // Clear Config & Uninstall Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("ระบบความปลอดภัยและการถอนการติดตั้ง (Uninstall / Clear Config)")
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("ล้างการตั้งค่าประวัติ (Clear Config):")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("จะลบประวัติ Presets ทั้งหมด, ไฟล์กำหนดความละเอียดหน้าจอแบบคัสตอมที่สร้างโดยแอพนี้ และกู้คืนไฟล์แบ็คอัพดั้งเดิมของระบบกลับคืนมา")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("ล้างประวัติการตั้งค่าทั้งหมด (Clear Config)") {
                        let alert = NSAlert()
                        alert.messageText = "ยืนยันการล้างข้อมูลทั้งหมด?"
                        alert.informativeText = "การดำเนินการนี้จะกู้คืนไฟล์ระบบ แบ็คอัพดั้งเดิม และรีเซ็ตความชอบของระบบทั้งหมด"
                        alert.addButton(withTitle: "ยืนยัน")
                        alert.addButton(withTitle: "ยกเลิก")
                        let res = alert.runModal()
                        if res == .alertFirstButtonReturn {
                            ClearConfigService.shared.performClearConfig(confirmBackupsRestore: true) { result in
                                switch result {
                                case .success:
                                    alertMessage = "รีเซ็ตและล้างการตั้งค่าทั้งหมดของ Mac Monitor สำเร็จ"
                                    showingAlert = true
                                    manager.refreshDisplays()
                                case .failure(let err):
                                    alertMessage = "พบข้อผิดพลาดในการล้างการตั้งค่า: \(err.localizedDescription)"
                                    showingAlert = true
                                }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer().frame(height: 10)
                    
                    Text("ถอนการติดตั้งโปรแกรมแบบสมบูรณ์ (Complete Uninstall):")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("ทำการล้างการตั้งค่า คืนค่าแบ็คอัพดั้งเดิม ลบโฟลเดอร์ Application Support, Logs, Caches และพรีเฟอเรนซ์ไฟล์ของ Mac Monitor ทั้งหมดแบบหมดจดถาวร")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("ถอนการติดตั้ง Mac Monitor (Uninstall)") {
                        let alert = NSAlert()
                        alert.messageText = "ยืนยันการถอนการติดตั้งแอพพลิเคชัน?"
                        alert.informativeText = "แอพจะถูกทำความสะอาดและปิดตัวลง รายงานสรุปผลจะแสดงในขั้นตอนสุดท้าย"
                        alert.addButton(withTitle: "ยืนยันการถอนการติดตั้ง")
                        alert.addButton(withTitle: "ยกเลิก")
                        let res = alert.runModal()
                        if res == .alertFirstButtonReturn {
                            UninstallService.shared.performUninstall { result in
                                switch result {
                                case .success(let report):
                                    uninstallReportText = report
                                    showingUninstallReport = true
                                case .failure(let err):
                                    alertMessage = "การถอนการติดตั้งล้มเหลว: \(err.localizedDescription)"
                                    showingAlert = true
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}
