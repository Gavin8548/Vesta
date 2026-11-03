//
//  LaunchSafety.swift
//
//  冷启动开关。为 false 时不创建菜单栏、性能浮窗、主题壁纸，
//  也不在界面刷新时扫描磁盘或容器。确认能稳定打开后，再改为 true。
//

enum LaunchSafety {
    static let backgroundServicesEnabled = false
}
