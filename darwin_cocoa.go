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
#import "darwin_cocoa.h"

static void nslog(const char *s) {
	NSLog(@"%s", s);
	free((void *)s);
}

static void * newDelegate(void * context, void * window, const char * url, bool debug) {
	NSString * _urlstr = [[NSString alloc] initWithUTF8String:url];
	NSURL *_url = [[NSURL alloc] initWithString:_urlstr];
	WebViewDelegate * del = [[WebViewDelegate alloc] initWithContext:context window:window url:_url debug:debug];
	free((void *)url);
	[_url release];
	[_urlstr release];
	return del;
}

static void delegateRelease(void * self) {
	[(WebViewDelegate *)self release];
}

static void delegateEvalNoFree(void * self, void * handler, const char *js) {
	NSString * _js = [[NSString alloc] initWithUTF8String:js];
	[(WebViewDelegate *)self evaluateJavaScript:_js completionHandler:handler];
	[_js release];
}

static void delegateEval(void * del, void * handler, const char *js) {
	delegateEvalNoFree(del, handler, js);
	free((void *)js);
}

static void delegateInjectCSS(void * del, void * handler, const char *css) {
	injectCSS(del, handler, css, delegateEvalNoFree);
	free((void *)css);
}

static void delegateDialog(void * self, enum webview_dialog_type type, int flags, const char *title, const char *arg, char *result, size_t resultsz) {
    NSString *_title = [[NSString alloc] initWithUTF8String:title];
    NSString *_arg = [[NSString alloc] initWithUTF8String:arg];
    NSString *nsresult = [(WebViewDelegate *)self dialog:type flags:flags title:_title arg:_arg];
	strlcpy(result, nsresult.UTF8String, resultsz);
	free((void *)title);
	free((void *)arg);
	[_title release];
	[_arg release];
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
)

func debug(a ...interface{}) {
	C.nslog(C.CString(fmt.Sprint(a...)))
}

func debugf(format string, a ...interface{}) {
	C.nslog(C.CString(fmt.Sprintf(format, a...)))
}

type webview struct {
	mu        sync.RWMutex
	delegate  unsafe.Pointer
	callbacks []ExternalInvokeCallbackFunc
}

func newWebView(window *app.Window, url string, debug bool) *webview {
	w := new(webview)
	w.delegate = C.newDelegate(unsafe.Pointer(w), window.Handle(), C.CString(url), C.bool(debug))
	runtime.SetFinalizer(w, finalizeWebView)
	return w
}

func finalizeWebView(w *webview) {
	C.delegateRelease(w.delegate)
}

//export webviewCallback
func webviewCallback(ptr unsafe.Pointer, cdata *C.char) {
	w := (*webview)(ptr)
	if w == nil {
		return
	}

	w.mu.RLock()
	cbs := w.callbacks
	w.mu.RUnlock()

	if len(cbs) == 0 {
		return
	}

	data := C.GoString(cdata)
	for _, cb := range cbs {
		cb(w, data)
	}
}

func (w *webview) addCallback(cb ExternalInvokeCallbackFunc) {
	w.mu.Lock()
	w.callbacks = append(w.callbacks, cb)
	w.mu.Unlock()
}

func (w *webview) Dialog(typ DialogType, flags int, title, arg string) string {
	const maxPath = 4096
	result := (*C.char)(C.calloc((C.size_t)(unsafe.Sizeof((*C.char)(nil))), (C.size_t)(maxPath)))
	defer C.free(unsafe.Pointer(result))

	C.delegateDialog(w.delegate, C.enum_webview_dialog_type(typ), C.int(flags), C.CString(title), C.CString(arg), result, C.size_t(maxPath))
	return C.GoString(result)
}

func (w *webview) Eval(js string) (err error) {
	done := make(chan struct{})

	app.Dispatch(func() {
		C.delegateEval(w.delegate, cgo.Save(func(description, message, url string, line, col int) {
			if description == "" {
				close(done)
				return
			}

			if message == "" {
				err = errors.New(description)
				close(done)
				return
			}

			scanner := bufio.NewScanner(strings.NewReader(js))
			for i := 0; scanner.Scan(); i++ {
				if i+1 == line {
					break
				}
			}

			text := strings.TrimSuffix(scanner.Text(), "\n")
			if text == "" {
				err = fmt.Errorf("%s: %s (line %d, col %d)", description, message, line, col)
				close(done)
				return
			}

			if col < len(text) {
				err = fmt.Errorf("%s: %s (line %d, col %d):\n%s", description, message, line, col, text)
				close(done)
				return
			}

			err = fmt.Errorf("%s: %s (line %d, col %d):\n%s>%s", description, message, line, col, text[:col], text[col:])
			close(done)
		}).C(), C.CString(js))
	})

	<-done
	return
}

func (w *webview) InjectCSS(css string) (err error) {
	done := make(chan struct{})

	app.Dispatch(func() {
		C.delegateInjectCSS(w.delegate, cgo.Save(func(description, message, url string, line, col int) {
			if description == "" {
				close(done)
				return
			}

			err = fmt.Errorf("%s", description)
			close(done)
		}).C(), C.CString(css))
	})

	<-done
	return
}

//export javaScriptEvaluationComplete
func javaScriptEvaluationComplete(ref unsafe.Pointer, description, message, url *C.char, line, col C.int) {
	r := cgo.Reference(ref)
	r.Load().(func(description, message, url string, line, col int))(C.GoString(description), C.GoString(message), C.GoString(url), int(line), int(col))
	r.Delete()
}
