import os.log

public enum AppLog {
    public static let subsystem = "com.m96chan.KTApple"

    public static func logger(for category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
