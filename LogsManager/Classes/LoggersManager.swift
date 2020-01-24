//
//  LoggersManager.swift
//  LogsManager
//
//  Created by Anton Plebanovich on 3/2/18.
//  Copyright © 2018 Anton Plebanovich. All rights reserved.
//

import Foundation

#if COCOAPODS
import CocoaLumberjack
#else
import CocoaLumberjackSwift
#endif

/// Central point for all application logs.
/// You can easily change how logs will be displayed or processed here.
open class LoggersManager {
    
    // ******************************* MARK: - Singleton
    
    public static var shared: LoggersManager = LoggersManager()
    
    // ******************************* MARK: - Private Properties
    
    private var logComponents: [LogComponent] = []
    private var cachedComponents: [ComponentsKey: [LogComponent]] = [:]
    private let queue = DispatchQueue(label: "LoggersManager", attributes: .concurrent)
    
    /// Default file logger. You can adjust its parameters if needed.
    /// By default, each app session corresponds to individual file, max logs size is 300 MB
    /// and all logs are saved.
    public private(set) lazy var fileLogger: FileLogger = {
        
        // Record all `verbose` level logs into file
        let fileLogger = FileLogger(mode: .all, logLevel: .verbose)
        
        // Each app session should correspond to one log file
        fileLogger.maximumFileSize = .max
        fileLogger.doNotReuseLogFiles = true
        fileLogger.rollingFrequency = .greatestFiniteMagnitude
        fileLogger.logFileManager.logFilesDiskQuota = 300 * 1024 * 1024 // 300 MB
        fileLogger.logFileManager.maximumNumberOfLogFiles = .max
        
        // Log logs file destination on simulators for ease access during debug sessions.
        if TARGET_OS_SIMULATOR != 0 {
            logInfo("Log file path: \"\(fileLogger.currentLogFileInfo.filePath)\"")
        }
        
        return fileLogger
    }()
    
    // ******************************* MARK: - Initialization and Setup
    
    public init() {
        setup()
    }
    
    private func setup() {
        
    }
    
    // ******************************* MARK: - Public Methods
    
    /// Registers log component for detection
    public func registerLogComponent(_ logComponent: LogComponent) {
        guard !logComponents.contains(logComponent) else {
            print("Log component '\(logComponent)' was already added")
            return
        }
        
        logComponents.append(logComponent)
        cachedComponents = [:]
    }
    
    /// Uregisters log component from detection
    public func unregisterLogComponent(_ logComponent: LogComponent) {
        guard logComponents.contains(logComponent) else {
            print("Log component '\(logComponent)' is not added")
            return
        }
        
        logComponents.remove(logComponent)
        cachedComponents = [:]
    }
    
    /// Adds text logger
    public func addLogger(_ logger: BaseLogger) {
        DDLog.add(logger, with: logger.logLevel)
    }
    
    /// Removes text logger
    public func removeLogger(_ logger: BaseLogger) {
        DDLog.remove(logger)
    }
    
    /// Adds default file logger. Check `fileLogger` property for more details.
    public func addFileLogger() {
        guard !DDLog.allLoggers.contains(where: { $0 === fileLogger }) else { return }
        addLogger(fileLogger)
    }
    
    /// Removes previously added `fileLogger`.
    public func removeFileLogger() {
        guard DDLog.allLoggers.contains(where: { $0 === fileLogger }) else { return }
        removeLogger(fileLogger)
    }
    
    /// Log message function.
    /// - parameter message: Message to log.
    /// - parameter logComponents: Components this log belongs to, e.g. `.network`, `.keychain`, ... . Autodetect if `nil`.
    /// - parameter flag: Log level, e.g. `.error`, `.debug`, ...
    public func logMessage(_ message: @autoclosure () -> String, logComponents: [LogComponent]? = nil, flag: DDLogFlag, file: String = #file, function: String = #function, line: UInt = #line) {
        let logComponents = logComponents ?? detectLogComponent(filePath: file, function: function, line: line)
        let parameters = DDLogMessage.Parameters(data: nil, error: nil, logComponents: logComponents)
        
        // -------- Copied from `CocoaLumberjack.swift`
        // The `dynamicLogLevel` will always be checked here (instead of being passed in).
        // We cannot "mix" it with the `DDDefaultLogLevel`, because otherwise the compiler won't strip strings that are not logged.
        if dynamicLogLevel.rawValue & flag.rawValue != 0 {
            // Tell the DDLogMessage constructor to copy the C strings that get passed to it.
            let logMessage = DDLogMessage(message: message(),
                                          level: DDLogLevel(flag: flag),
                                          flag: flag,
                                          context: 0,
                                          file: file,
                                          function: function,
                                          line: line,
                                          tag: parameters,
                                          options: [.copyFile, .copyFunction],
                                          timestamp: nil)
            
            DDLog.sharedInstance.log(asynchronous: false, message: logMessage)
        }
        // --------
    }
    
    /// Log error function.
    /// - parameter message: Message to log.
    /// - parameter logComponents: Components this log belongs to, e.g. `.network`, `.keychain`, ... . Autodetect if `nil`.
    /// - parameter error: Error that occured.
    /// - parameter data: Data to attach to error.
    /// - parameter flag: Log level, e.g. `.error`, `.debug`, ...
    public func logError(_ message: @autoclosure () -> String, logComponents: [LogComponent]? = nil, error: Any?, data: [String: Any?]?, file: String = #file, function: String = #function, line: UInt = #line) {
        let logComponents = logComponents ?? detectLogComponent(filePath: file, function: function, line: line)
        let parameters = DDLogMessage.Parameters(data: data, error: error, logComponents: logComponents)
        
        // -------- Copied from `CocoaLumberjack.swift`
        // The `dynamicLogLevel` will always be checked here (instead of being passed in).
        // We cannot "mix" it with the `DDDefaultLogLevel`, because otherwise the compiler won't strip strings that are not logged.
        if dynamicLogLevel.rawValue & DDLogFlag.error.rawValue != 0 {
            // Tell the DDLogMessage constructor to copy the C strings that get passed to it.
            let logMessage = DDLogMessage(message: message(),
                                          level: .error,
                                          flag: .error,
                                          context: 0,
                                          file: file,
                                          function: function,
                                          line: line,
                                          tag: parameters,
                                          options: [.copyFile, .copyFunction],
                                          timestamp: nil)
            
            DDLog.sharedInstance.log(asynchronous: false, message: logMessage)
        }
        // -------- 
    }
    
    // ******************************* MARK: - Private Methods
    
    private func detectLogComponent(filePath: String, function: String, line: UInt) -> [LogComponent] {
        // Return hash if we have
        let key = ComponentsKey(filePath: filePath, function: function, line: line)
        let existingCachedComponents: [LogComponent]? = queue.sync {
            if let cachedComponents = cachedComponents[key] {
                return cachedComponents
            } else {
                return nil
            }
        }
        
        if let existingCachedComponents = existingCachedComponents {
            return existingCachedComponents
        }
        
        var components: [LogComponent] = logComponents
            .filter { logComponent in
                let path = String(filePath)
                let file = String.getFileName(filePath: path)
                let function = String(function)
                return logComponent.isLogForThisComponent(path, file, function)
        }
        
        if components.isEmpty {
            components.append(.unspecified)
        }
        
        queue.async(flags: .barrier) {
            self.cachedComponents[key] = components
        }
        
        return components
    }
}

private struct ComponentsKey: Equatable, Hashable {
    let filePath: String
    let function: String
    let line: UInt
}
