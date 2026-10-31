import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window as QQW
import RinUI

QQW.Window {    id: carrier
    visible: true
    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    modality: Qt.ApplicationModal

    property var choices: typeof authOptions !== "undefined" ? authOptions : []
    property string dialogIcon: typeof authDialogIcon !== "undefined" ? authDialogIcon : "ic_fluent_shield_keyhole_20_filled"
    property string dialogIconColor: typeof authDialogIconColor !== "undefined" ? authDialogIconColor : ""


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
        width: Math.max(360, Screen.width * 0.22)
        title: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("身份验证")

        QQC2.Overlay.modal: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        // 图标 + 说明文案并排（宿主对话框同款布局）
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Icon {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                size: 42
                name: carrier.dialogIcon
                color: carrier.dialogIconColor !== ""
                    ? carrier.dialogIconColor
                    : Theme.currentTheme.colors.primaryColor
            }
            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                typography: Typography.Body
                text: typeof authPrompt !== "undefined" ? authPrompt : qsTr("请选择一种验证方式")
                wrapMode: Text.WordWrap
            }
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
