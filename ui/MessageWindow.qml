import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import RinUI

// 通知弹窗：居中普通窗口 + RinUI 主题外观（圆角、雾面背景、投影）。
QQC2.Window {
    id: messageWindow

    modality: Qt.ApplicationModal
    visible: true
    title: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("身份验证")
    width: 400
    height: 220
    minimumWidth: 400
    minimumHeight: 220
    maximumWidth: 400
    maximumHeight: 220


    Rectangle {
        anchors.fill: parent
        color: Theme.currentTheme.colors.backgroundAcrylicColor
        border.color: Theme.currentTheme.colors.windowBorderColor
        border.width: 1
        radius: Theme.currentTheme.appearance.windowRadius
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            Icon {
                size: 24
                name: "ic_fluent_info_20_filled"
                color: Theme.currentTheme.colors.systemAttentionColor
            }

            Text {
                typography: Typography.Title
                text: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("身份验证")
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.currentTheme.colors.dividerBorderColor
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            typography: Typography.Body
            text: typeof authPrompt !== "undefined" ? authPrompt : ""
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            color: Theme.currentTheme.colors.textSecondaryColor
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            text: typeof authSubmitLabel !== "undefined" ? authSubmitLabel : qsTr("确定")
            highlighted: true
            onClicked: authContext.cancel()
        }
    }

    onClosing: (close) => {
        close.accepted = true
        authContext.cancel()
    }
}
