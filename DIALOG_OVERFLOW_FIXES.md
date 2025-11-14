# Dialog Overflow Fixes - code_editor.dart

## Issue
When typing in text fields within AlertDialogs in the code editor, there was a 160px bottom overflow, especially when the keyboard appeared on mobile devices.

## Root Cause
The original AlertDialogs were using `SingleChildScrollView` directly inside, but without proper constraints. When the keyboard appeared, it would push the dialog content down, causing overflow on small screens.

## Solution
Wrapped all TextFielddialog boxes with:
```dart
Dialog(
  child: ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: 400,
      maxHeight: MediaQuery.of(context).size.height * 0.5, // or 0.6 for larger dialogs
    ),
    child: SingleChildScrollView(
      child: AlertDialog(
        // ... content
      ),
    ),
  ),
)
```

## Fixed Dialogs

### 1. **Create New File Dialog** (Line 86)
- **File**: `lib/parts/code_editor.dart`
- **Method**: `_startNewFile()`
- **Fix**: 
  - Wrapped AlertDialog in Dialog + ConstrainedBox
  - maxHeight: 50% of screen height
  - maxWidth: 400px

### 2. **Save As New File Dialog** (Line 316)
- **File**: `lib/parts/code_editor.dart`
- **Method**: `_saveAsNewRoom()`
- **Fix**:
  - Wrapped AlertDialog in Dialog + ConstrainedBox
  - maxHeight: 60% of screen height (larger for description field)
  - maxWidth: 400px

### 3. **Update File Info Dialog** (Line 417)
- **File**: `lib/parts/code_editor.dart`
- **Method**: `_updateRoomInfo()`
- **Fix**:
  - Wrapped AlertDialog in Dialog + ConstrainedBox
  - maxHeight: 60% of screen height
  - maxWidth: 400px

## Benefits

✅ Prevents keyboard from pushing dialog off-screen
✅ Allows scrolling if content exceeds max height
✅ Works on all device sizes (320px to 2000px+)
✅ Proper constraint handling
✅ Clean, maintainable code structure

## Testing

Test these scenarios:
- [ ] Small phones (320px - 400px)
- [ ] Regular phones (400px - 600px)
- [ ] Tablets (600px+)
- [ ] Both portrait and landscape orientations
- [ ] Open dialog and type long text
- [ ] Open dialog, focus field, and check keyboard behavior
