import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RinUI
import ClassWidgets.Plugins

PluginPage {
    id: root
    pluginId: "authentication.lyang1273"
    title: qsTr("登录选项")

    property bool hasPassword: false
    property bool hasHello: false
    property bool helloReady: false
    property bool syncing: false

    // --- Flyout 相关属性 ---
    property string infoText: ""
    property int infoSeverity: Severity.Warning

    Timer {
        id: infoTimer
        interval: 4000
        onTriggered: infoFlyout.close()
    }

    // 使用 Timer 延迟初始化，避免窗口渲染时死锁
    Timer {
        id: initTimer
        interval: 100
        onTriggered: refresh()
    }

    Component.onCompleted: initTimer.start()

    // 核心：QML 内部触发提示的方法
    function showInfo(msg, sev) {
        root.infoText = msg
        root.infoSeverity = sev
        infoFlyout.open()
        infoTimer.restart()
    }

    // 辅助判断：当前是否有任何触发事件被开启
    function anyEventEnabled() {
        return startupSwitch.checked || settingsSwitch.checked || editorSwitch.checked ||
               installSwitch.checked || updateSwitch.checked || exitSwitch.checked
    }

    // 辅助判断：能否移除某个认证方式
    function checkCanRemove(isPassword) {
        var hasOther = isPassword ? root.hasHello : root.hasPassword
        if (!hasOther && anyEventEnabled()) {
            showInfo("至少保留一种认证方式，或先关闭所有触发验证的事件。", Severity.Warning)
            return false
        }
        return true
    }

    Connections {
        target: root.backend
        function onStateChanged() { root.refresh() }
    }

    function refresh() {
        if (!root.backend) return
        root.syncing = true
        root.hasPassword = root.backend.has_auth_method("password")
        root.hasHello = root.backend.has_auth_method("hello")
        root.helloReady = root.backend.hello_available()
        startupSwitch.checked = root.backend.get_event_enabled("startup")
        settingsSwitch.checked = root.backend.get_event_enabled("settings")
        editorSwitch.checked = root.backend.get_event_enabled("course_editor")
        installSwitch.checked = root.backend.get_event_enabled("install_uninstall")
        updateSwitch.checked = root.backend.get_event_enabled("update")
        exitSwitch.checked = root.backend.get_event_enabled("exit")
        root.syncing = false
    }

    // =========================================
    // 原生 Flyout (无自定义背景、无定位)
    // =========================================
    Flyout {
        id: infoFlyout
        parent: root
        modal: false

        RowLayout {
            spacing: 12
            Icon {
                size: 20
                name: root.infoSeverity === Severity.Error ? "ic_fluent_error_circle_20_filled" :
                      root.infoSeverity === Severity.Warning ? "ic_fluent_warning_20_filled" :
                      root.infoSeverity === Severity.Success ? "ic_fluent_checkmark_circle_20_filled" : "ic_fluent_info_20_filled"
                color: root.infoSeverity === Severity.Error ? Theme.currentTheme.colors.systemCriticalColor :
                       root.infoSeverity === Severity.Warning ? Theme.currentTheme.colors.systemAttentionColor :
                       root.infoSeverity === Severity.Success ? Theme.currentTheme.colors.systemSuccessColor : Theme.currentTheme.colors.primaryColor
            }
            Text {
                text: root.infoText
                typography: Typography.Body
                wrapMode: Text.WordWrap
                color: Theme.currentTheme.colors.textPrimaryColor
            }
        }
    }
    // =========================================

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        Text {
            Layout.fillWidth: true
            text: qsTr("管理你验证身份的方式")
            typography: Typography.BodyStrong
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("选择一种验证方式，添加、更改或移除它。恶意的外部人员免受攻击保护你的西大不丢额的安全")
            typography: Typography.Caption
            color: Theme.currentTheme.colors.textSecondaryColor
            wrapMode: Text.WordWrap
        }

        SettingCard {
            Layout.fillWidth: true
            icon.name: "ic_fluent_fingerprint_20_regular"
            title: qsTr("Windows Hello")
            description: !root.helloReady
                ? qsTr("此选项当前不可用 - 这真是让人尴尬 目前，我们无法配置 Windows Hello ，确保你已设置 Windows Hello 在你的设备上。")
                : (root.hasHello ? qsTr("已添加 - 使用 Windows Hello 生物识别或 PIN 验证身份。")
                                 : qsTr("未添加 - 使用 Windows Hello 生物识别或 PIN 验证身份。"))

            Button {
                text: qsTr("添加")
                visible: root.helloReady && !root.hasHello
                highlighted: true
                onClicked: {
                    if (root.backend) {
                        if (!root.backend.add_auth_method("hello")) {
                            showInfo("无法添加 Windows Hello：不可用或验证被拒绝。", Severity.Error)
                        }
                    }
                }
            }
            Button {
                text: qsTr("移除")
                visible: root.hasHello
                onClicked: {
                    if (root.backend && checkCanRemove(false)) {
                        root.backend.remove_auth_method("hello")
                    }
                }
            }
        }

        SettingCard {
            Layout.fillWidth: true
            icon.name: "ic_fluent_password_20_regular"
            title: qsTr("密码")
            description: root.hasPassword
                ? qsTr("已添加 - 使用你的本地密码验证身份。")
                : qsTr("未添加 - 设置一个用于校验的本地密码。")

            Button {
                text: qsTr("更改")
                visible: root.hasPassword
                onClicked: {
                    if (root.backend && root.backend.configure_password()) {
                        showInfo("验证密码已保存。", Severity.Success)
                    }
                }
            }
            Button {
                text: qsTr("添加")
                visible: !root.hasPassword
                highlighted: true
                onClicked: {
                    if (root.backend) {
                        root.backend.add_auth_method("password")
                    }
                }
            }
            Button {
                text: qsTr("移除")
                visible: root.hasPassword
                onClicked: {
                    if (root.backend && checkCanRemove(true)) {
                        root.backend.remove_auth_method("password")
                    }
                }
            }
        }

        Text {
            Layout.topMargin: 12
            Layout.fillWidth: true
            text: qsTr("验证触发时机")
            typography: Typography.BodyStrong
        }

        SettingCard {
            Layout.fillWidth: true
            icon.name: "ic_fluent_calendar_settings_20_regular"
            title: qsTr("程序启动时")
            description: qsTr("插件加载时立即进行身份验证。")

            Switch {
                id: startupSwitch
                onToggled: {
                    if (root.backend && !root.syncing) {
                        if (!root.backend.set_event_enabled("startup", checked)) {
                            showInfo("启用验证触发项前，请先添加至少一种认证方式。", Severity.Warning)
                            root.syncing = true
                            checked = false
                            root.syncing = false
                        }
                    }
                }
            }
        }

        SettingExpander {
            Layout.fillWidth: true
            icon.name: "ic_fluent_calendar_settings_20_regular"
            title: qsTr("其他触发时机")
            description: qsTr("选择需要进行身份验证的其他操作")

            SettingItem {
                title: qsTr("打开设置时")
                description: qsTr("每次打开设置窗口前需要验证身份")
                Switch {
                    id: settingsSwitch
                    onToggled: {
                        if (root.backend && !root.syncing) {
                            if (!root.backend.set_event_enabled("settings", checked)) {
                                showInfo("启用验证触发项前，请先添加至少一种认证方式。", Severity.Warning)
                                root.syncing = true
                                checked = false
                                root.syncing = false
                            }
                        }
                    }
                }
            }
            SettingItem {
                title: qsTr("打开课程编辑时")
                description: qsTr("每次打开课程编辑窗口前需要验证身份")
                Switch {
                    id: editorSwitch
                    onToggled: {
                        if (root.backend && !root.syncing) {
                            if (!root.backend.set_event_enabled("course_editor", checked)) {
                                showInfo("启用验证触发项前，请先添加至少一种认证方式。", Severity.Warning)
                                root.syncing = true
                                checked = false
                                root.syncing = false
                            }
                        }
                    }
                }
            }
            SettingItem {
                title: qsTr("安装/卸载插件时")
                description: qsTr("导入、安装、卸载、更新或启用/禁用任意插件前需要验证身份")
                Switch {
                    id: installSwitch
                    onToggled: {
                        if (root.backend && !root.syncing) {
                            if (!root.backend.set_event_enabled("install_uninstall", checked)) {
                                showInfo("启用验证触发项前，请先添加至少一种认证方式。", Severity.Warning)
                                root.syncing = true
                                checked = false
                                root.syncing = false
                            }
                        }
                    }
                }
            }
            SettingItem {
                title: qsTr("更新插件或程序时")
                description: qsTr("程序包下载完成后，开始安装更新前需要验证身份")
                Switch {
                    id: updateSwitch
                    onToggled: {
                        if (root.backend && !root.syncing) {
                            if (!root.backend.set_event_enabled("update", checked)) {
                                showInfo("启用验证触发项前，请先添加至少一种认证方式。", Severity.Warning)
                                root.syncing = true
                                checked = false
                                root.syncing = false
                            }
                        }
                    }
                }
            }
            SettingItem {
                title: qsTr("退出程序时")
                description: qsTr("退出或重启 Class Widgets 前需要验证身份")
                Switch {
                    id: exitSwitch
                    onToggled: {
                        if (root.backend && !root.syncing) {
                            if (!root.backend.set_event_enabled("exit", checked)) {
                                showInfo("启用验证触发项前，请先添加至少一种认证方式。", Severity.Warning)
                                root.syncing = true
                                checked = false
                                root.syncing = false
                            }
                        }
                    }
                }
            }
        }

        InfoBar {
            Layout.fillWidth: true
            title: qsTr("认证说明")
            text: qsTr("密码使用 PBKDF2-HMAC-SHA256 哈希保存。添加 Windows Hello 需要通过一次实时验证。")
            severity: Severity.Info
        }
    }
}