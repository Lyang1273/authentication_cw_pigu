import QtQuick 2.15
import QtQuick.Layouts 2.15
import RinUI

Window {
    id: messageWindow

    modality: Qt.ApplicationModal
    visible: false
    title: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("确保那是你")
    width: 360
    height: 200
    minimumWidth: 360
    minimumHeight: 200
    maximumWidth: 360
    maximumHeight: 200

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        Icon {
            name: "ic_fluent_info_20_regular"
            size: 28
            color: Theme.currentTheme.colors.textSecondaryColor
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            typography: Typography.BodyStrong
            text: typeof authTitle !== "undefined" && authTitle !== "" ? authTitle : qsTr("确保那是你")
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            typography: Typography.Body
            text: typeof authPrompt !== "undefined" ? authPrompt : ""
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignTop
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
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
