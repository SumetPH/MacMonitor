import SwiftUI

public struct DiagnosticsView: View {
    @ObservedObject private var manager = DisplayManager.shared
    @State private var recentLogs: [DisplayOperationResult] = []
    @State private var showingExportAlert = false
    @State private var exportedFilePath = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            Text("ระบบวินิจฉัยและบันทึกเหตุการณ์ (Diagnostics & Logs)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // System Information
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ข้อมูลระบบระบบปฏิบัติการ (OS Info)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                            .font(.body)
                        Text("เครื่อง Apple Silicon: \(isAppleSilicon() ? "ใช่ (Yes)" : "ไม่ใช่ (No)")")
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Displays list details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("สถานะหน้าจอเชื่อมต่อ (Connected Displays)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        ForEach(manager.displays) { display in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• \(display.name) (ID: \(display.displayID))")
                                    .fontWeight(.semibold)
                                Text("  - UUID: \(display.identifier.uuid ?? "ไม่มี (None)")")
                                Text("  - ขนาดภาพ (Logical): \(display.currentWidth)x\(display.currentHeight) | ขนาดพิกเซล: \(display.currentPixelWidth)x\(display.currentPixelHeight)")
                                Text("  - เฟรมเรต: \(display.refreshRate) Hz | HiDPI: \(display.isHiDPI ? "ใช่ (Retina)" : "ไม่ใช่")")
                                Text("  - การหมุนจอ: \(display.rotation) องศา | เชื่อมต่อผ่าน DDC/CI: \(DDCService.shared.supportsDDC(displayID: display.displayID) ? "รองรับ" : "ไม่รองรับ")")
                            }
                            .font(.footnote)
                            .padding(.leading, 8)
                        }
                    }
                    
                    // Application Logs
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("บันทึกประวัติการทำงาน (Operation Logs)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                            Button("ล้างประวัติ (Clear Logs)") {
                                DiagnosticsService.shared.clearLogs()
                                loadLogs()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                        
                        if recentLogs.isEmpty {
                            Text("ไม่มีการบันทึกประวัติเหตุการณ์ในขณะนี้")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(recentLogs.reversed()) { log in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(log.success ? "🟢 [สำเร็จ]" : "🔴 [ล้มเหลว]")
                                                .fontWeight(.bold)
                                            Text(log.operationType)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(formatDate(log.timestamp))
                                                .foregroundColor(.secondary)
                                        }
                                        Text(log.details)
                                        if let err = log.errorDescription {
                                            Text("ข้อผิดพลาด: \(err)")
                                                .foregroundColor(.red)
                                        }
                                        Divider()
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            HStack {
                Spacer()
                Button("ส่งออกรายงานประวัติ (Export Diagnostics)") {
                    exportReport()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            loadLogs()
        }
        .alert(isPresented: $showingExportAlert) {
            Alert(
                title: Text("ส่งออกรายงานสำเร็จ"),
                message: Text("บันทึกไฟล์รายงานไว้ที่:\n\(exportedFilePath)"),
                dismissButton: .default(Text("ตกลง"))
            )
        }
    }
    
    private func loadLogs() {
        recentLogs = DiagnosticsService.shared.getLogs()
    }
    
    private func isAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func exportReport() {
        let report = DiagnosticsService.shared.generateReport(displays: manager.displays)
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let fileURL = desktop.appendingPathComponent("MacMonitor_Diagnostics_Report.txt")
        
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            exportedFilePath = fileURL.path
            showingExportAlert = true
        } catch {
            print("[DiagnosticsView] Failed to export: \(error.localizedDescription)")
        }
    }
}
