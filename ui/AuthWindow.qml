import QtQuick 2.15
import QtQuick.Window as QQW
import QtQuick.Controls as QQC2
import QtQuick.Layouts 2.15
import RinUI

// Transparent carrier window so the RinUI Dialog and its dimmed overlay
// cover the whole screen (host's CheckSingleInstanceDialog pattern).
QQW.Window {
    id: carrier
    visible: true
    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint | Qt.WA_TranslucentBackground
    modality: Qt.ApplicationModal

    property string errorMessage: ""
    property bool revealPassword: false
    // echoMode enums: RinUI shadows QtQuick's TextInput type, so use numeric values.
    property int echoNormal: 0
    property int echoPassword: 2

    // RinUI Dialog 的 Overlay.modal 雾化遮罩在半透明窗口上不渲染，
    // 因此这里自行绘制全屏变暗背景。
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    function showFeedback(message) {
        carrier.errorMessage = message
        passwordInput.text = ""
        passwordInput.forceActiveFocus()
    }

    Connections {
        target: typeof authContext !== "undefined" ? authContext : null
        function onFeedback(message) {
            carrier.showFeedback(message)
        }
    }

    Dialog {
        id: authDialog
        width: Screen.width * 0.22
        title: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("确保那是你")

        QQC2.Overlay.modal: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        Text {
            Layout.fillWidth: true
            typography: Typography.Body
            text: typeof authPrompt !== "undefined" ? authPrompt : qsTr("验证你的身份以继续使用 Class Widgets。")
            wrapMode: Text.WordWrap
            color: Theme.currentTheme.colors.textSecondaryColor
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            TextField {
                id: passwordInput
                Layout.fillWidth: true
                echoMode: carrier.revealPassword ? carrier.echoNormal : carrier.echoPassword
                placeholderText: qsTr("输入密码")
                clearEnabled: false
                onTextChanged: carrier.errorMessage = ""
                onActiveFocusChanged: if (activeFocus) selectAll()
                onAccepted: authContext.accept(text)
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

            Button {
                text: qsTr("取消")
                Layout.preferredWidth: parent.width * 0.5
                onClicked: authContext.cancel()
            }

            Button {
                id: okButton
                text: typeof authSubmitLabel !== "undefined" ? authSubmitLabel : qsTr("确定")
                highlighted: true
                Layout.preferredWidth: parent.width * 0.5
                onClicked: authContext.accept(passwordInput.text)
            }
        }

        onClosed: authContext.cancel()

        Component.onCompleted: {
            passwordInput.forceActiveFocus()
            authDialog.open()
        }
    }
}
