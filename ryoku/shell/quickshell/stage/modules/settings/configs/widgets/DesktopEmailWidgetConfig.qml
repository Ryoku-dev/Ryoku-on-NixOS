import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.settings.configs.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack
    property bool credentialDraftsLoaded: false
    property bool credentialSaveFailed: false
    property bool credentialSaved: false

    function saveCredentials() {
        if (credentialsSaver.running
                || clientIdField.inputText.trim().length === 0
                || clientSecretField.inputText.trim().length === 0)
            return;
        root.credentialSaveFailed = false;
        root.credentialSaved = false;
        credentialsSaver.command = [
            "python3",
            Directories.stageScriptPath + "/email/backup_gmail_env.py",
            clientIdField.inputText.trim(),
            clientSecretField.inputText.trim()
        ];
        credentialsSaver.running = true;
    }

    Component.onCompleted: credentialsLoader.running = true

    Process {
        id: credentialsLoader
        command: ["python3", Directories.stageScriptPath + "/email/get_gmail_credentials.py"]
        stdout: StdioCollector {
            id: credentialsOutput
            onStreamFinished: {
                try {
                    const data = JSON.parse(credentialsOutput.text);
                    clientIdField.inputText = String(data.client_id ?? "");
                    clientSecretField.inputText = String(data.client_secret ?? "");
                } catch (error) {
                    clientIdField.inputText = "";
                    clientSecretField.inputText = "";
                }
                root.credentialDraftsLoaded = true;
            }
        }
    }

    Process {
        id: credentialsSaver
        onExited: (exitCode, exitStatus) => {
            root.credentialSaveFailed = exitCode !== 0;
            root.credentialSaved = exitCode === 0;
            if (exitCode === 0)
                EmailService.checkCredentials();
        }
    }

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Email Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Email Widget Settings")
        icon: "mail"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("email_inbox")
                && !Config.isWidgetActive("email_inbox_2x1")

            PagePlaceholder {
                anchors.fill: parent
                icon: "mail"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Email Widget disabled")
                description: Translation.tr("Enable the Email Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("email_inbox")
                || Config.isWidgetActive("email_inbox_2x1")
            ContentSubsectionLabel {
                text: Translation.tr("Gmail account")
            }

            StyledText {
                Layout.fillWidth: true
                text: EmailService.credentialsConfigured
                    ? Translation.tr("Gmail OAuth credentials are configured.")
                    : Translation.tr("Gmail setup required")
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("To use Gmail, provide your own Google OAuth Client ID and Client Secret. Create a Desktop App OAuth client with the Gmail API enabled, then save both values here.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 42
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: Translation.tr("Open Google Cloud Console")
                        color: Appearance.colors.colOnLayer2
                    }
                }

                onClicked: Spawn.runApp(["xdg-open", "https://console.cloud.google.com/apis/credentials"], { label: "browser" })
            }

            ConfigTextField {
                id: clientIdField
                text: Translation.tr("Google OAuth Client ID")
                icon: "badge"
                placeholderText: Translation.tr("Client ID")
                enabled: root.credentialDraftsLoaded && !credentialsSaver.running
            }

            ConfigTextField {
                id: clientSecretField
                text: Translation.tr("Google OAuth Client Secret")
                icon: "key"
                placeholderText: Translation.tr("Client Secret")
                enabled: root.credentialDraftsLoaded && !credentialsSaver.running
                textField.echoMode: TextInput.Password
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                enabled: root.credentialDraftsLoaded
                    && !credentialsSaver.running
                    && clientIdField.inputText.trim().length > 0
                    && clientSecretField.inputText.trim().length > 0
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: credentialsSaver.running ? "progress_activity" : "save"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledText {
                        text: credentialsSaver.running
                            ? Translation.tr("Saving...")
                            : Translation.tr("Save Gmail credentials")
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.DemiBold
                    }
                }

                onClicked: root.saveCredentials()
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.credentialSaveFailed || root.credentialSaved
                text: root.credentialSaveFailed
                    ? Translation.tr("Could not save Gmail credentials.")
                    : Translation.tr("Gmail credentials saved. You can now sign in.")
                color: root.credentialSaveFailed
                    ? Appearance.colors.colError : Appearance.colors.colPrimary
                wrapMode: Text.Wrap
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                visible: EmailService.credentialsConfigured && !EmailService.authenticated
                enabled: !EmailService.authenticating && !EmailService.checkingCredentials
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: EmailService.authenticating ? "hourglass_empty" : "login"
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        text: EmailService.authenticating
                            ? Translation.tr("Waiting for browser...")
                            : Translation.tr("Sign in to Gmail")
                        color: Appearance.colors.colOnSecondaryContainer
                        font.weight: Font.DemiBold
                    }
                }

                onClicked: EmailService.startOAuth()
            }

            StyledText {
                Layout.fillWidth: true
                visible: EmailService.authenticating
                text: Translation.tr("Complete the sign-in in your browser window.")
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }


            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
