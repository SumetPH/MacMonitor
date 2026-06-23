import SwiftUI

public struct DiagnosticsView: View {
    @ObservedObject private var manager = DisplayManager.shared
    @State private var recentLogs: [DisplayOperationResult] = []
    @State private var showingExportAlert = false
    @State private var exportedFilePath = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            Text("Diagnostics & System Logs")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // System Information
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Operating System Information")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                            .font(.body)
                        Text("Apple Silicon Machine: \(isAppleSilicon() ? "Yes" : "No")")
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Displays list details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connected Displays Status")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        ForEach(manager.displays) { display in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• \(display.name) (ID: \(display.displayID))")
                                    .fontWeight(.semibold)
                                Text("  - UUID: \(display.identifier.uuid ?? "None")")
                                Text("  - Logical Mode: \(display.currentWidth)x\(display.currentHeight) | Physical Resolution: \(display.currentPixelWidth)x\(display.currentPixelHeight)")
                                Text("  - Refresh Rate: \(Int(display.refreshRate)) Hz | HiDPI: \(display.isHiDPI ? "Yes (Retina)" : "No")")
                                Text("  - Rotation: \(display.rotation)° | DDC/CI Control: \(DDCService.shared.supportsDDC(displayID: display.displayID) ? "Supported" : "Not Supported")")
                            }
                            .font(.footnote)
                            .padding(.leading, 8)
                        }
                    }
                    
                    // Application Logs
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Application Operation Logs")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                            Button("Clear Logs") {
                                DiagnosticsService.shared.clearLogs()
                                loadLogs()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                        
                        if recentLogs.isEmpty {
                            Text("No events recorded yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(recentLogs.reversed()) { log in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(log.success ? "🟢 [Success]" : "🔴 [Failure]")
                                                .fontWeight(.bold)
                                            Text(log.operationType)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(formatDate(log.timestamp))
                                                .foregroundColor(.secondary)
                                        }
                                        Text(log.details)
                                        if let err = log.errorDescription {
                                            Text("Error: \(err)")
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
                Button("Export Diagnostics Report") {
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
                title: Text("Export Successful"),
                message: Text("Diagnostics report saved to:\n\(exportedFilePath)"),
                dismissButton: .default(Text("OK"))
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
