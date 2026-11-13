#!/bin/bash
# Stops the build if the app uses any control that iOS draws itself. Those are drawn mirrored
# in Arabic (their text reads backwards), so the app uses its own SwiftUI versions instead:
#   long-press menus, dialogs, alerts  -> ActionMenu (.actionMenu / .onLongPress)
#   date and time pickers              -> DayPickerPopup / TimePickerPopup
#   Form / List                        -> ScrollView with cards
#   segmented / menu pickers, Menu     -> app-drawn chips and segments
#   navigation pushes                  -> sheets and SlidePage
set -u
cd "$(dirname "$0")/.."
patterns=(
  '\.contextMenu'
  '\.confirmationDialog'
  '\.alert\('
  '\.actionSheet'
  'DatePicker\('
  '\bPicker\('
  '\bMenu *\{'
  '\bMenu\('
  '\bForm *\{'
  '\bList *\{'
  '\bList\('
  'NavigationLink'
  'UIAlertController'
  'UIMenu\b'
)
found=0
for p in "${patterns[@]}"; do
  if grep -rnE "$p" Sources --include='*.swift' | grep -vE '^\S+:[0-9]+:\s*//'; then
    found=1
  fi
done
if [ $found -ne 0 ]; then
  echo "::error::A control drawn by iOS was used (it shows mirrored in Arabic). Use the app's own version instead — see scripts/check-rtl.sh."
  exit 1
fi
echo "RTL check passed: no iOS-drawn menus, dialogs, pickers or lists."
