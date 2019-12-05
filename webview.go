/*
 * MIT License
 *
 * Copyright (c) 2019 The WebView Authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

package webview

/*
#include "webview.h"
*/
import "C"

// DialogType is an enumeration of all supported system dialog types
type DialogType int

const (
	// DialogTypeOpen is a system file open dialog
	DialogTypeOpen DialogType = iota
	// DialogTypeSave is a system file save dialog
	DialogTypeSave
	// DialogTypeAlert is a system alert dialog (message box)
	DialogTypeAlert
)

const (
	// DialogFlagFile is a normal file picker dialog
	DialogFlagFile = C.WEBVIEW_DIALOG_FLAG_FILE
	// DialogFlagDirectory is an open directory dialog
	DialogFlagDirectory = C.WEBVIEW_DIALOG_FLAG_DIRECTORY
	// DialogFlagInfo is an info alert dialog
	DialogFlagInfo = C.WEBVIEW_DIALOG_FLAG_INFO
	// DialogFlagWarning is a warning alert dialog
	DialogFlagWarning = C.WEBVIEW_DIALOG_FLAG_WARNING
	// DialogFlagError is an error dialog
	DialogFlagError = C.WEBVIEW_DIALOG_FLAG_ERROR
)
