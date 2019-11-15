package webview

/*
#cgo linux openbsd freebsd CFLAGS: -DLINUX -DGTK
#cgo windows CFLAGS: -DWINDOWS
#cgo darwin CFLAGS: -DDARWIN
#include "webview.h"
*/
import "C"
import "runtime"

func init() {
	// Lock the goroutine responsible for initialization to an OS thread.
	// This means the goroutine running main (and calling runApp below)
	// is locked to the OS thread that started the program. This is
	// necessary for the correct delivery of Cocoa events to the process.
	//
	// A discussion on this topic:
	// https://groups.google.com/forum/#!msg/golang-nuts/IiWZ2hUuLDA/SNKYYZBelsYJ
	runtime.LockOSThread()
}

// Debug prints a debug string using stderr on Linux/BSD, NSLog on MacOS and
// OutputDebugString on Windows.
func Debug(a ...interface{}) {
	debug(a...)
}

// Debugf prints a formatted debug string using stderr on Linux/BSD, NSLog on
// MacOS and OutputDebugString on Windows.
func Debugf(format string, a ...interface{}) {
	debugf(format, a...)
}

// ExternalInvokeCallbackFunc is a function type that is called every time
// "window.external.invoke()" is called from JavaScript. Data is the only
// obligatory string parameter passed into the "invoke(data)" function from
// JavaScript. To pass more complex data serialized JSON or base64 encoded
// string can be used.
type ExternalInvokeCallbackFunc func(w WebView, data string)

// Settings is a set of parameters to customize the initial WebView appearance
// and behavior. It is passed into the webview.New() constructor.
type Settings struct {
	// WebView main window title
	Title string
	// URL to open in a webview
	URL string
	// Window width in pixels
	Width int
	// Window height in pixels
	Height int
	// Allows/disallows window resizing
	Resizable bool
	// Enable debugging tools (Linux/BSD/MacOS, on Windows use Firebug)
	Debug bool
	// A callback that is executed when JavaScript calls "window.external.invoke()"
	ExternalInvokeCallback ExternalInvokeCallbackFunc
}

// WebView is an interface that wraps the basic methods for controlling the UI
// loop, handling multithreading and providing JavaScript bindings.
type WebView interface {
	// Run() starts the main UI loop until the user closes the webview window or
	// Terminate() is called.
	Run()
	// Loop() runs a single iteration of the main UI.
	Loop(blocking bool) bool
	// SetTitle() changes window title. This method must be called from the main
	// thread only. See Dispatch() for more details.
	SetTitle(title string)
	// SetFullscreen() controls window full-screen mode. This method must be
	// called from the main thread only. See Dispatch() for more details.
	SetFullscreen(fullscreen bool)
	// SetColor() changes window background color. This method must be called from
	// the main thread only. See Dispatch() for more details.
	SetColor(r, g, b, a uint8)
	// Eval() evaluates an arbitrary JS code inside the webview. This method must
	// be called from the main thread only. See Dispatch() for more details.
	Eval(js string) error
	// InjectJS() injects an arbitrary block of CSS code using the JS API. This
	// method must be called from the main thread only. See Dispatch() for more
	// details.
	InjectCSS(css string)
	// Dialog() opens a system dialog of the given type and title. String
	// argument can be provided for certain dialogs, such as alert boxes. For
	// alert boxes argument is a message inside the dialog box.
	Dialog(dlgType DialogType, flags int, title string, arg string) string
	// Terminate() breaks the main UI loop. This method must be called from the main thread
	// only. See Dispatch() for more details.
	Terminate()
	// Dispatch() schedules some arbitrary function to be executed on the main UI
	// thread. This may be helpful if you want to run some JavaScript from
	// background threads/goroutines, or to terminate the app.
	Dispatch(func())
	// Exit() closes the window and cleans up the resources. Use Terminate() to
	// forcefully break out of the main UI loop.
	Exit()
	// Bind() registers a binding between a given value and a JavaScript object with the
	// given name.  A value must be a struct or a struct pointer. All methods are
	// available under their camel-case names, starting with a lower-case letter,
	// e.g. "FooBar" becomes "fooBar" in JavaScript.
	// Bind() returns a function that updates JavaScript object with the current
	// Go value. You only need to call it if you change Go value asynchronously.
	Bind(name string, v interface{}) (sync func(), err error)
}

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

// Open is a simplified API to open a single native window with a full-size webview in
// it. It can be helpful if you want to communicate with the core app using XHR
// or WebSockets (as opposed to using JavaScript bindings).
//
// Window appearance can be customized using title, width, height and resizable parameters.
// URL must be provided and can user either a http or https protocol, or be a
// local file:// URL. On some platforms "data:" URLs are also supported
// (Linux/MacOS).
func Open(title, url string, width, height int, resizable bool) error {
	w := newWebView(title, url, width, height, resizable, false)
	w.Run()
	w.Exit()
	return nil
}

// New creates and opens a new webview window using the given settings. The
// returned object implements the WebView interface. This function returns nil
// if a window can not be created.
func New(settings Settings) WebView {
	if settings.Width == 0 {
		settings.Width = 640
	}
	if settings.Height == 0 {
		settings.Height = 480
	}
	if settings.Title == "" {
		settings.Title = "WebView"
	}

	w := newWebView(settings.Title, settings.URL, settings.Width, settings.Height, settings.Resizable, settings.Debug)
	if w == nil {
		return nil
	}

	if settings.ExternalInvokeCallback != nil {
		w.addCallback(settings.ExternalInvokeCallback)
	}
	return w
}

func (w *webview) Run() {
	for w.Loop(true) {
	}
}
