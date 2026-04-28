/*
    SPDX-FileCopyrightText: 2012-2013 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2021 Fushan Wen <qydwhotmail@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    TPO: Change height to screen height
*/

import QtQuick 2.15
// Deliberately imported after QtQuick to avoid missing restoreMode property in Binding. Fix in Qt 6.
import QtQml 2.15
import QtQml.Models 2.15
import QtQuick.Window 2.15

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.draganddrop 2.0
import org.kde.kitemmodels 1.0
import org.kde.taskmanager 0.1 as TaskManager

import "code/layout.js" as LayoutManager

PlasmaCore.Dialog {
    id: groupDialog
    visible: true

    type: PlasmaCore.Dialog.PopupMenu
    flags: Qt.WindowStaysOnTopHint
    hideOnWindowDeactivate: true
    location: plasmoid.location

    readonly property real preferredWidth: Screen.width / (3 * Screen.devicePixelRatio)
    // OLD: readonly property real preferredHeight: Screen.height / (2 * Screen.devicePixelRatio)
    // TODO: make the scaling factor an option
    // TPO:
    readonly property real preferredHeight: Screen.height / Screen.devicePixelRatio
    // GPT:
    // readonly property real preferredHeight: groupDialog.Screen.availableGeometry.height
    // 					       / groupDialog.Screen.devicePixelRatio
    readonly property real contentWidth: mainItem.width // No padding here to avoid text elide.

    property alias overflowing: scrollView.overflowing
    property var _oldAppletStatus: PlasmaCore.Types.UnknownStatus

    KSortFilterProxyModel {
        id: groupProxyModel
        sourceModel: tasksModel
        sortRole: "display"
        sortOrder: Qt.AscendingOrder
    }

    function findActiveTaskIndex() {
        if (!tasksModel.activeTask) {
            return;
        }
        const activeProxyIndex = groupProxyModel.mapFromSource(tasksModel.activeTask);
        for (let i = 0; i < groupListView.count; i++) {
            if (groupFilter.items.get(i).modelIndex === activeProxyIndex) {
                groupListView.positionViewAtIndex(i, ListView.Contain); // Prevent visual glitches
                groupListView.currentIndex = i;
                return;
            }
        }
    }

    mainItem: MouseHandler {
        id: mouseHandler
        width: Math.min(groupDialog.preferredWidth, Math.max(groupListView.maxWidth, groupDialog.visualParent.width))
        // OLD: height: Math.min(groupDialog.preferredHeight, groupListView.maxHeight)
	// GPT:
	height: Math.min(groupDialog.preferredHeight, groupListView.contentHeight)

        target: groupListView
        handleWheelEvents: !scrollView.overflowing
        isGroupDialog: true

        Keys.onEscapePressed: groupDialog.visible = false

        function moveRow(event, insertAt) {
            if (!(event.modifiers & Qt.ControlModifier) || !(event.modifiers & Qt.ShiftModifier)) {
                event.accepted = false;
                return;
            } else if (insertAt < 0 || insertAt >= groupListView.count) {
                return;
            }

            // Manual reordering in an alphabetically sorted list is confusing and often disabled.
            // However, we keep the original logic but mapping indices back to source might be needed.
            // For now, we use the original tasksModel directly for moves.
            const parentModelIndex = tasksModel.makeModelIndex(groupDialog.visualParent.itemIndex);
            const sourceIndex = groupFilter.items.get(groupListView.currentIndex).modelIndex;
            const mappedIndex = groupProxyModel.mapToSource(sourceIndex);

            const status = tasksModel.move(mappedIndex.row, insertAt, parentModelIndex);
            if (!status) {
                return;
            }

            groupListView.currentIndex = insertAt;
        }

        PlasmaComponents3.ScrollView {
            id: scrollView
            anchors.fill: parent
            readonly property bool overflowing: leftPadding > 0 || rightPadding > 0 // Scrollbar is visible

            PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

            ListView {
                id: groupListView

                readonly property real maxWidth: groupFilter.maxTextWidth
                                                + LayoutManager.horizontalMargins()
						// TPO: uses small to squeeze in more icons (see Task.qml)
                                                // OLD: + PlasmaCore.Units.iconSizes.medium
						+ PlasmaCore.Units.iconSizes.small
                                                + 2 * (LayoutManager.labelMargin + LayoutManager.iconMargin)
                                                + scrollView.leftPadding + scrollView.rightPadding
                // Use groupFilter.count because sometimes count is not updated in time (BUG 446105)
                // OLD: readonly property real maxHeight: groupFilter.count * (LayoutManager.verticalMargins() + Math.max(theme.mSize(theme.defaultFont).height, PlasmaCore.Units.iconSizes.medium))
		readonly property real maxHeight: groupFilter.count * (LayoutManager.verticalMargins() + Math.max(theme.mSize(theme.defaultFont).height, PlasmaCore.Units.iconSizes.small))

                model: DelegateModel {
                    id: groupFilter

                    readonly property TextMetrics textMetrics: TextMetrics {}
                    property real maxTextWidth: 0

                    model: groupProxyModel
                    rootIndex: groupProxyModel.mapFromSource(tasksModel.makeModelIndex(groupDialog.visualParent.itemIndex))
                    delegate: Task {
                        width: groupListView.width
                        visible: true
                        inPopup: true

                        ListView.onRemove: Qt.callLater(groupFilter.updateMaxTextWidth)
                        Connections {
                            enabled: index < 20 // 20 is based on performance considerations.

                            function onLabelTextChanged() { // ListView.onAdd included
                                if (groupFilter.maxTextWidth === 0) {
                                    // Update immediately to avoid shrinking
                                    groupFilter.updateMaxTextWidth();
                                } else {
                                    Qt.callLater(groupFilter.updateMaxTextWidth);
                                }
                            }
                        }
                    }

                    function updateMaxTextWidth() {
                        let tempMaxTextWidth = 0;
                        // 20 is based on performance considerations.
                        for (let i = 0; i < Math.min(count, 20); i++) {
                            textMetrics.text = items.get(i).model.display;
                            if (textMetrics.boundingRect.width > tempMaxTextWidth) {
                                tempMaxTextWidth = textMetrics.boundingRect.width;
                            }
                        }
                        maxTextWidth = tempMaxTextWidth;
                    }
                }

                reuseItems: false

                Keys.onUpPressed: mouseHandler.moveRow(event, groupListView.currentIndex - 1);
                Keys.onDownPressed: mouseHandler.moveRow(event, groupListView.currentIndex + 1);

                onCountChanged: {
                    if (count > 0) {
                        backend.cancelHighlightWindows()
                    } else {
                        groupDialog.visible = false;
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            _oldAppletStatus = plasmoid.status;
            plasmoid.status = PlasmaCore.Types.RequiresAttentionStatus;

            groupDialog.requestActivate();
            groupListView.forceActiveFocus(); // Active focus on ListView so keyboard navigation can work.
            Qt.callLater(findActiveTaskIndex);
        } else {
            plasmoid.status = _oldAppletStatus;
            tasks.groupDialog = null;
            destroy();
        }
    }
}
