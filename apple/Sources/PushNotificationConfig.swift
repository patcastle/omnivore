import App
import Firebase
import FirebaseMessaging
import Foundation
import Models
import Services
import UIKit
import Utils

extension AppDelegate {
  func configureFirebase() {
    guard FeatureFlag.enablePushNotifications else { return }

    let keys: FirebaseKeys? = {
      let isProd = (PublicValet.storedAppEnvironment ?? .initialAppEnvironment) == .prod
      let firebaseKeys = isProd ? AppKeys.sharedInstance?.firebaseProdKeys : AppKeys.sharedInstance?.firebaseDemoKeys
      return firebaseKeys ?? AppKeys.sharedInstance?.firebaseProdKeys
    }()

    guard let keys = keys else { return }

    let firebaseOpts = FirebaseOptions(googleAppID: keys.googleAppID, gcmSenderID: keys.gcmSenderID)

    firebaseOpts.storageBucket = keys.storageBucket
    firebaseOpts.projectID = keys.projectID
    firebaseOpts.bundleID = keys.bundleID
    firebaseOpts.apiKey = keys.apiKey
    firebaseOpts.clientID = keys.clientID

    FirebaseApp.configure(options: firebaseOpts)
    FirebaseConfiguration.shared.setLoggerLevel(.min)

    if UserDefaults.standard.bool(forKey: UserDefaultKey.notificationsEnabled.rawValue) {
      registerForNotifications()
    }
  }

  func registerForNotifications() {
    Messaging.messaging().delegate = self
    UNUserNotificationCenter.current().delegate = self
    UIApplication.shared.registerForRemoteNotifications()
  }

  func unregisterForNotifications() {
    Messaging.messaging().delegate = nil
    UNUserNotificationCenter.current().delegate = nil
    UIApplication.shared.unregisterForRemoteNotifications()
  }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
    @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    UIApplication.shared.applicationIconBadgeNumber = 0
    print(userInfo) // extract data sent along with PN
    completionHandler([[.banner, .sound]])
  }

  func userNotificationCenter(
    _: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo

    if let linkData = userInfo["link"] as? String {
      guard let jsonData = Data(base64Encoded: linkData) else { return }

      if let article = try? JSONDecoder().decode(JSONArticle.self, from: jsonData) {
        NSNotification.pushJSONArticle(article: article)
      }
    }

    completionHandler()
  }

  func application(
    _: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
  }

  func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print(error.localizedDescription)
  }
}

extension AppDelegate: MessagingDelegate {
  func messaging(
    _: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {
    guard let fcmToken = fcmToken else { return }

    let savedToken = UserDefaults.standard.string(forKey: UserDefaultKey.firebasePushToken.rawValue)
    let deviceTokenID = UserDefaults.standard.string(forKey: UserDefaultKey.deviceTokenID.rawValue)

    // If the deviceTokenID is null, that means we haven't set our token yet, and this is just
    // a previously saved token.
    if savedToken == fcmToken, deviceTokenID != nil {
      return
    }

    Task {
      try? await Services().dataService.syncDeviceToken(deviceTokenOperation: .addToken(token: fcmToken))
    }
  }
}
