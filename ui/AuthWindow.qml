import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window as QQW
import RinUI

QQW.Window {
    id: carrier
    visible: true

    width: QQW.Screen.width
    height: QQW.Screen.height + 1
    color: "transparent"
    flags: Qt.FramelessWindowHint
    modality: Qt.ApplicationModal

    property string errorMessage: ""
    property bool revealPassword: false
    property bool submitted: false
    property int echoNormal: 0
    property int echoPassword: 2

    property string dialogIcon: (typeof authDialogIcon !== "undefined" && authDialogIcon !== "") ? authDialogIcon : "ic_fluent_person_key_20_filled"
    property string dialogIconColor: typeof authDialogIconColor !== "undefined" ? authDialogIconColor : ""

    function hasAuthContext() {
        return typeof authContext !== "undefined" && authContext !== null
    }

    function submitAuth(text) {
        if (!carrier.hasAuthContext())
            return
        carrier.submitted = true
        authContext.accept(text)
    }

    function cancelAuth() {
        if (!carrier.hasAuthContext())
            return
        authContext.cancel()
    }

    function showFeedback(message) {
        passwordInput.text = ""
        carrier.errorMessage = message
        passwordInput.forceActiveFocus()
    }

    // 自绘全屏变暗背景，避免原生 Overlay 不生效
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    Connections {
        target: typeof authContext !== "undefined" ? authContext : null
        function onFeedback(message) { carrier.showFeedback(message) }
    }

    Dialog {
        id: authDialog
        width: Math.max(360, QQW.Screen.width * 0.22)
        title: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("确保那是你")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Icon {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 42; Layout.preferredHeight: 42; size: 42
                name: carrier.dialogIcon
                color: carrier.dialogIconColor !== "" ? carrier.dialogIconColor : Theme.currentTheme.colors.textSecondaryColor
            }
            Text {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                typography: Typography.Body
                text: typeof authPrompt !== "undefined" ? authPrompt : qsTr("验证你的身份以继续使用 Class Widgets。")
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 // 稍微调小间距，让图标和输入框显得紧凑

            // 触摸键盘图标按钮
            Button {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                icon.name: "ic_fluent_keyboard_20_regular"
                flat: true // 设为扁平，去掉默认背景
                onClicked: {
                    // 1. 先让输入框获取焦点
                    passwordInput.forceActiveFocus()
                    // 2. 调用 Python 后端拉起 Windows 触摸键盘
                    if (carrier.hasAuthContext() && typeof authContext.show_keyboard !== "undefined") {
                        authContext.show_keyboard()
                    }
                }
            }

            TextField {
                id: passwordInput
                Layout.fillWidth: true
                echoMode: carrier.revealPassword ? carrier.echoNormal : carrier.echoPassword
                placeholderText: qsTr("输入密码")
                clearEnabled: false
                onTextChanged: carrier.errorMessage = ""
                onActiveFocusChanged: if (activeFocus) selectAll()
                onAccepted: carrier.submitAuth(text)
            }

            CheckBox {
                text: qsTr("显示密码")
                checked: carrier.revealPassword
                onToggled: carrier.revealPassword = checked
            }
        }

        Text {
            id: errorHint
            Layout.fillWidth: true
            visible: carrier.errorMessage !== ""
            text: carrier.errorMessage
            typography: Typography.Caption
            color: Theme.currentTheme.colors.systemCriticalColor
            wrapMode: Text.WordWrap
        }

        footer: DialogButtonBox {
            padding: 15
            Button { text: qsTr("取消"); Layout.fillWidth: true; onClicked: carrier.cancelAuth() }
            Button {
                text: typeof authSubmitLabel !== "undefined" ? authSubmitLabel : qsTr("确定")
                highlighted: true; Layout.fillWidth: true
                onClicked: carrier.submitAuth(passwordInput.text)
            }
        }

        onClosed: { if (!carrier.submitted) carrier.cancelAuth() }
    }

    Component.onCompleted: {
        passwordInput.forceActiveFocus()
        authDialog.open()
    }
}