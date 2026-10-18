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

    property var choices: typeof authOptions !== "undefined" ? authOptions : []

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

    Dialog {
        id: methodDialog
        width: Screen.width * 0.22
        title: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("确保那是你")

        QQC2.Overlay.modal: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        Text {
            Layout.fillWidth: true
            typography: Typography.Body
            text: typeof authPrompt !== "undefined" ? authPrompt : qsTr("请选择一种验证方式")
            wrapMode: Text.WordWrap
            color: Theme.currentTheme.colors.textSecondaryColor
        }

        Repeater {
            model: carrier.choices
            delegate: Button {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                icon.name: modelData.key === "hello"
                    ? "ic_fluent_fingerprint_20_regular"
                    : "ic_fluent_password_20_regular"
                text: modelData.label
                onClicked: {
                    methodDialog.close()
                    authContext.accept(modelData.key)
                }
            }
        }

        footer: DialogButtonBox {
            padding: 15

            Button {
                text: qsTr("取消")
                Layout.fillWidth: true
                Layout.preferredWidth: parent.width
                onClicked: authContext.cancel()
            }
        }

        onClosed: authContext.cancel()

        Component.onCompleted: methodDialog.open()
    }
}
