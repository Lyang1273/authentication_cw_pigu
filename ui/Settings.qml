import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RinUI
import ClassWidgets.Plugins

PluginPage {
    id: root
    // Hardcoded: the packaged host's NavigationSubItem does not forward {pluginId}.
    pluginId: "authentication.lyang1273"
    title: qsTr("登录选项")

    property bool hasPassword: false
    property bool hasHello: false
    property bool helloReady: false
    property bool syncing: false

    Component.onCompleted: refresh()

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
            text: qsTr("选择一种验证方式，添加、更改或移除它。启用验证时任一方式通过即可。")
            typography: Typography.Caption
            color: Theme.currentTheme.colors.textSecondaryColor
            wrapMode: Text.WordWrap
        }

        // —— 认证方式列表（仿 Windows 登录选项）——
        SettingCard {
            Layout.fillWidth: true
            icon.name: "ic_fluent_fingerprint_20_regular"
            title: qsTr("Windows Hello")
            description: !root.helloReady
                ? qsTr("此选项当前不可用 - 此设备不支持或未配置 Windows Hello。")
                : (root.hasHello ? qsTr("已添加 - 使用 Windows Hello 生物识别或 PIN 验证身份。")
                                 : qsTr("未添加 - 使用 Windows Hello 生物识别或 PIN 验证身份。"))

            Button {
                text: qsTr("添加")
                visible: root.helloReady && !root.hasHello
                highlighted: true
                onClicked: if (root.backend) root.backend.add_auth_method("hello")
            }
            Button {
                text: qsTr("移除")
                visible: root.hasHello
                onClicked: if (root.backend) root.backend.remove_auth_method("hello")
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
                onClicked: if (root.backend) root.backend.configure_password()
            }
            Button {
                text: qsTr("添加")
                visible: !root.hasPassword
                highlighted: true
                onClicked: if (root.backend) root.backend.add_auth_method("password")
            }
            Button {
                text: qsTr("移除")
                visible: root.hasPassword
                onClicked: if (root.backend) root.backend.remove_auth_method("password")
            }
        }

        // —— 验证触发时机（仿 Windows 安全性部分）——
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
                onToggled: if (root.backend && !root.syncing) root.backend.set_event_enabled("startup", checked)
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
                    onToggled: if (root.backend && !root.syncing) root.backend.set_event_enabled("settings", checked)
                }
            }
            SettingItem {
                title: qsTr("打开课程编辑时")
                description: qsTr("每次打开课程编辑窗口前需要验证身份")
                Switch {
                    id: editorSwitch
                    onToggled: if (root.backend && !root.syncing) root.backend.set_event_enabled("course_editor", checked)
                }
            }
            SettingItem {
                title: qsTr("安装/卸载插件时")
                description: qsTr("导入、安装、卸载、更新或启用/禁用任意插件前需要验证身份")
                Switch {
                    id: installSwitch
                    onToggled: if (root.backend && !root.syncing) root.backend.set_event_enabled("install_uninstall", checked)
                }
            }
            SettingItem {
                title: qsTr("更新插件或程序时")
                description: qsTr("程序包下载完成后，开始安装更新前需要验证身份")
                Switch {
                    id: updateSwitch
                    onToggled: if (root.backend && !root.syncing) root.backend.set_event_enabled("update", checked)
                }
            }
            SettingItem {
                title: qsTr("退出程序时")
                description: qsTr("退出或重启 Class Widgets 前需要验证身份")
                Switch {
                    id: exitSwitch
                    onToggled: if (root.backend && !root.syncing) root.backend.set_event_enabled("exit", checked)
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
