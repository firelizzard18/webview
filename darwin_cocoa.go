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

// +build darwin
// +build !gtk

package webview

/*
#import "webview.h"
#import <WebKit/WebKit.h>

@interface WebViewDelegate : NSObject
- (NSString *) dialog:(enum webview_dialog_type)type flags:(int)flags title:(NSString *)title arg:(NSString *)arg;
@end

void * newWebView(void * context, void * config, void * window);
void evaluateJavaScript(void * self, void * js, void * handler);

static void * newConfiguration() {
	return [WKWebViewConfiguration new];
}

static void enableDebug(void * self) {
	[[(WKWebViewConfiguration *)self preferences] setValue:@YES forKey:@"developerExtrasEnabled"];
}

static void load(void * self, void * url) {
	[(WKWebView *)self loadRequest:[NSURLRequest requestWithURL:url]];
}

static void * dialog(void * self, enum webview_dialog_type type, int flags, void *title, void *arg) {
    return [(WebViewDelegate *)self dialog:type flags:flags title:(NSString *)title arg:(NSString *)arg];
}
*/
import "C"

import (
	"bufio"
	"errors"
	"fmt"
	"runtime"
	"strings"
	"sync"
	"unsafe"

	"gitlab.com/firelizzard/go-app"
	"gitlab.com/firelizzard/go-app/cgo"
	"gitlab.com/firelizzard/go-app/objc"
)

type Settings struct {
	id unsafe.Pointer
}

func NewSettings() *Settings {
	s := &Settings{C.newConfiguration()}
	runtime.SetFinalizer(s, (*Settings).release)
	return s
}
func (s *Settings) release() {
	objc.Release(s.id)
}

func (s *Settings) EnableDebug() {
	C.enableDebug(s.id)
}

type WebView struct {
	id        unsafe.Pointer
	ref       cgo.Reference
	mu        sync.RWMutex
	callbacks []func(string)
}

// New creates a new WKWebView.
//
// The webview and its delegate will be released when the Go object is no longer
// referenced. To avoid any issues, retain a reference to the Go object.
func New(window *app.Window, settings *Settings) *WebView {
	wv := new(WebView)
	wv.ref = cgo.Save(wv)
	wv.id = C.newWebView(wv.ref.C(), settings.id, window.Handle())

	runtime.SetFinalizer(wv, (*WebView).release)
	return wv
}

func (w *WebView) release() {
	objc.Release(w.id)
	w.ref.Delete()
}

func (w *WebView) Load(url string) {
	u := objc.NSURL(url)
	defer objc.Release(u)
	C.load(w.id, u)
}

func (w *WebView) evaluationComplete(js, description, message, url string, line, col int) error {
	if description == "" {
		return nil
	}

	if message == "" {
		return errors.New(description)
	}

	scanner := bufio.NewScanner(strings.NewReader(js))
	for i := 0; scanner.Scan(); i++ {
		if i+1 == line {
			break
		}
	}

	text := strings.TrimSuffix(scanner.Text(), "\n")
	if text == "" {
		return fmt.Errorf("%s: %s (line %d, col %d)", description, message, line, col)
	}

	if col < len(text) {
		return fmt.Errorf("%s: %s (line %d, col %d):\n%s", description, message, line, col, text)
	}

	return fmt.Errorf("%s: %s (line %d, col %d):\n%s>%s", description, message, line, col, text[:col], text[col:])
}

//export javaScriptEvaluationComplete
func javaScriptEvaluationComplete(ref unsafe.Pointer, description, message, url *C.char, line, col C.int) {
	r := cgo.Reference(ref)
	r.Load().(func(description, message, url string, line, col int))(C.GoString(description), C.GoString(message), C.GoString(url), int(line), int(col))
	r.Delete()
}

func (w *WebView) Evaluate(js string) (err error) {
	done := make(chan struct{})

	app.Dispatch(func() {
		s := objc.NSString(js)
		defer objc.Release(s)

		C.evaluateJavaScript(w.id, s, cgo.Save(func(description, message, url string, line, col int) {
			err = w.evaluationComplete(js, description, message, url, line, col)
			close(done)
		}).C())
	})

	<-done
	return
}

func (w *WebView) Dialog(typ DialogType, flags int, title, arg string) string {
	_title := objc.NSString(title)
	defer objc.Release(_title)

	_arg := objc.NSString(arg)
	defer objc.Release(_arg)

	r := C.dialog(objc.ValueForKey(w.id, "navigationDelegate"), C.enum_webview_dialog_type(typ), C.int(flags), _title, _arg)
	return objc.GoString(r)
}

//export webviewCallback
func webviewCallback(ref unsafe.Pointer, cdata *C.char) {
	wv := cgo.Reference(ref).Load().(*WebView)

	wv.mu.RLock()
	cbs := wv.callbacks
	wv.mu.RUnlock()

	if len(cbs) == 0 {
		return
	}

	data := C.GoString(cdata)
	for _, cb := range cbs {
		cb(data)
	}
}

func (w *WebView) AddCallback(cb func(string)) {
	w.mu.Lock()
	w.callbacks = append(w.callbacks, cb)
	w.mu.Unlock()
}
