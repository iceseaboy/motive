//
//  CloudKitModels.swift
//  Motive
//
//  Shared CloudKit models for cross-device communication
//  This file should be added to both Motive (macOS) and MotiveRemote (iOS) targets
//

import CloudKit
import Foundation

#if os(macOS)
import IOKit
#else
import UIKit
#endif

// MARK: - CloudKit Container

// CloudKit container ID - must match the container configured in Xcode
// Format: iCloud.{bundle-id-prefix}.{app-name}
let motiveCloudKitContainerID = "iCloud.velvetai.Motive"

/// Check if CloudKit entitlement is present in the app bundle
/// This prevents crashes when the app is signed without CloudKit capability
var hasCloudKitEntitlement: Bool {
    #if DEBUG
    return true  // Debug builds from Xcode have entitlements
    #else
    #if os(macOS)
    // For macOS release builds, check entitlements via codesign
    return FileManager.default.ubiquityIdentityToken != nil && hasCloudKitEntitlementInBundle()
    #else
    // For iOS, App Store apps always have proper entitlements
    return FileManager.default.ubiquityIdentityToken != nil
    #endif
    #endif
}

#if os(macOS)
/// Check if the app bundle was signed with CloudKit entitlements (macOS only)
private func hasCloudKitEntitlementInBundle() -> Bool {
    guard let executableURL = Bundle.main.executableURL else { return false }
    
    // Use codesign to check entitlements
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["-d", "--entitlements", ":-", executableURL.path]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            return output.contains("com.apple.developer.icloud-services") &&
                   output.contains("CloudKit")
        }
    } catch {
        // If we can't check, assume no entitlement to be safe
    }
    
    return false
}
#endif

/// CloudKit container - only access after checking hasCloudKitEntitlement
var motiveCloudKitContainer: CKContainer {
    CKContainer(identifier: motiveCloudKitContainerID)
}

/// CloudKit private database - only access after checking hasCloudKitEntitlement
var motivePrivateDatabase: CKDatabase {
    motiveCloudKitContainer.privateCloudDatabase
}

// MARK: - Device Identifier

func getDeviceIdentifier() -> String {
    #if os(macOS)
    // Get hardware UUID on macOS
    let platformExpert = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPlatformExpertDevice")
    )
    defer { IOObjectRelease(platformExpert) }
    
    if let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
        platformExpert,
        kIOPlatformUUIDKey as CFString,
        kCFAllocatorDefault,
        0
    ) {
        return (serialNumberAsCFString.takeUnretainedValue() as? String) ?? UUID().uuidString
    }
    return UUID().uuidString
    #else
    // Use identifierForVendor on iOS
    return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    #endif
}

// MARK: - Remote Command Model

/// Represents a command sent from iOS to Mac via CloudKit
struct RemoteCommand: Identifiable {
    let id: String
    let instruction: String
    let status: CommandStatus
    let createdAt: Date
    let senderDeviceId: String
    let targetDeviceId: String?
    
    // Status update fields
    let toolName: String?
    let progress: Double?
    let result: String?
    let errorMessage: String?
    let updatedAt: Date?
    
    enum CommandStatus: String {
        case pending = "pending"
        case running = "running"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
    }
    
    // MARK: - CloudKit Record Type
    static let recordType = "Command"
    
    // MARK: - CloudKit Field Keys
    enum FieldKey: String {
        case instruction
        case status
        case createdAt
        case senderDeviceId
        case targetDeviceId
        case toolName
        case progress
        case result
        case errorMessage
        case updatedAt
    }
    
    // MARK: - Initialize from CKRecord
    init(record: CKRecord) {
        self.id = record.recordID.recordName
        self.instruction = record[FieldKey.instruction.rawValue] as? String ?? ""
        self.status = CommandStatus(rawValue: record[FieldKey.status.rawValue] as? String ?? "pending") ?? .pending
        self.createdAt = record[FieldKey.createdAt.rawValue] as? Date ?? record.creationDate ?? Date()
        self.senderDeviceId = record[FieldKey.senderDeviceId.rawValue] as? String ?? ""
        self.targetDeviceId = record[FieldKey.targetDeviceId.rawValue] as? String
        self.toolName = record[FieldKey.toolName.rawValue] as? String
        self.progress = record[FieldKey.progress.rawValue] as? Double
        self.result = record[FieldKey.result.rawValue] as? String
        self.errorMessage = record[FieldKey.errorMessage.rawValue] as? String
        self.updatedAt = record[FieldKey.updatedAt.rawValue] as? Date
    }
    
    // MARK: - Create CKRecord for new command
    static func createRecord(instruction: String, targetDeviceId: String? = nil) -> CKRecord {
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[FieldKey.instruction.rawValue] = instruction
        record[FieldKey.status.rawValue] = CommandStatus.pending.rawValue
        record[FieldKey.createdAt.rawValue] = Date()
        record[FieldKey.senderDeviceId.rawValue] = getDeviceIdentifier()
        if let targetDeviceId = targetDeviceId {
            record[FieldKey.targetDeviceId.rawValue] = targetDeviceId
        }
        return record
    }
}

// MARK: - Remote Permission Request Model

/// Represents a permission request sent from Mac to iOS via CloudKit
struct RemotePermissionRequest: Identifiable, Equatable {
    let id: String
    let commandId: String
    let question: String
    let options: [String]
    let createdAt: Date
    let response: String?
    let respondedAt: Date?
    
    // MARK: - CloudKit Record Type
    static let recordType = "PermissionRequest"
    
    // MARK: - CloudKit Field Keys
    enum FieldKey: String {
        case commandId
        case question
        case options
        case createdAt
        case response
        case respondedAt
    }
    
    // MARK: - Initialize from CKRecord
    init(record: CKRecord) {
        self.id = record.recordID.recordName
        self.commandId = record[FieldKey.commandId.rawValue] as? String ?? ""
        self.question = record[FieldKey.question.rawValue] as? String ?? ""
        self.options = record[FieldKey.options.rawValue] as? [String] ?? []
        self.createdAt = record[FieldKey.createdAt.rawValue] as? Date ?? record.creationDate ?? Date()
        self.response = record[FieldKey.response.rawValue] as? String
        self.respondedAt = record[FieldKey.respondedAt.rawValue] as? Date
    }
    
    // MARK: - Create CKRecord for new permission request
    static func createRecord(commandId: String, question: String, options: [String]) -> CKRecord {
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[FieldKey.commandId.rawValue] = commandId
        record[FieldKey.question.rawValue] = question
        record[FieldKey.options.rawValue] = options
        record[FieldKey.createdAt.rawValue] = Date()
        return record
    }
}
