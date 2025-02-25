import Flutter
import UIKit
import UserNotifications

public final class FlanPlugin: NSObject, FlutterPlugin, FlanDarwinApi {
    private let dateFormatter: ISO8601DateFormatter

    override init() {
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = FlanPlugin()
        FlanDarwinApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin)
        registrar.publish(plugin)
    }

    func getNotificationSettings(completion: @escaping (Result<[String: String], Error>) -> Void) {
        let notificationCenter = UNUserNotificationCenter.current()
        Task {
            let settings = await notificationCenter.notificationSettings()
            completion(.success(Converter.notificationSettingsToMap(settings)))
        }
    }

    func requestAuthorization(
        options: [String], completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let options: UNAuthorizationOptions = options.reduce([]) { partialOptions, option in
            switch option {
            case "badge":
                return partialOptions.union(.badge)
            case "sound":
                return partialOptions.union(.sound)
            case "alert":
                return partialOptions.union(.alert)
            case "criticalAlert":
                return partialOptions.union(.criticalAlert)
            case "providesAppNotificationSettings":
                return partialOptions.union(.providesAppNotificationSettings)
            case "provisional":
                return partialOptions.union(.provisional)
            default:
                completion(
                    .failure(
                        PigeonError(
                            code: "InvalidArguments",
                            message: "Invalid option '\(option)' provided in argument 'options'.",
                            details: nil)))
                return partialOptions  // Ignore invalid options
            }
        }

        let notificationCenter = UNUserNotificationCenter.current()
        Task {
            do {
                let granted = try await notificationCenter.requestAuthorization(options: options)
                completion(.success((granted)))
            } catch {
                completion(
                    .failure(
                        PigeonError(
                            code: "UNNotificationError",
                            message: error.localizedDescription,
                            details: nil)))
            }
        }
    }

    func scheduleNotification(
        id: String, targetEpochSeconds: String, content: [String: Any?], repeats: Bool,
        timeSensitive: Bool, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let notification = UNMutableNotificationContent()
        notification.title = content["title"] as? String ?? ""
        notification.subtitle = content["subtitle"] as? String ?? ""
        notification.body = content["body"] as? String ?? ""
        notification.sound = UNNotificationSound.default
        if timeSensitive {
            notification.interruptionLevel = UNNotificationInterruptionLevel.timeSensitive
        }

        guard let targetEpochSeconds = Double(targetEpochSeconds) else {
            completion(
                .failure(
                    PigeonError(
                        code: "InvalidArguments",
                        message: "Invalid argument 'targetEpochSeconds' provided.",
                        details: nil)))
            return
        }

        let targetDate = Date(timeIntervalSince1970: targetEpochSeconds)
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: targetDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)

        let request = UNNotificationRequest(
            identifier: id,
            content: notification,
            trigger: trigger
        )

        let notificationCenter = UNUserNotificationCenter.current()
        Task {
            do {
                try await notificationCenter.add(request)
                completion(.success(()))
            } catch {
                completion(
                    .failure(
                        (PigeonError(
                            code: "UNNotificationError",
                            message: error.localizedDescription,
                            details: nil))))
            }
        }
    }

    func cancelNotifications(ids: [String]) throws {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func getScheduledNotifications(completion: @escaping (Result<[[String: Any?]], Error>) -> Void)
    {
        let notificationCenter = UNUserNotificationCenter.current()
        Task {
            let notificationRequests = await notificationCenter.pendingNotificationRequests()
            let output = notificationRequests.map { Converter.notificationRequestToMap($0) }

            completion(.success(output))
        }
    }
}
