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

extern void dispatchCallback(void *);

static void nslog(const char *s) {
	NSLog(@"%s", s);
	free((void *)s);
}

static void * newDelegate(void * context, const char *title, const char *url, int width, int height, bool resizable, bool debug) {
	NSURL *_url = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
	NSString *_title = [NSString stringWithUTF8String:title];
	return [[WebViewDelegate alloc] initWithContext:context url:_url title:_title width:width height:height resizable:resizable debug:debug];
	free((void *)url);
	free((void *)title);
}

static void delegateRelease(void * del) {
	WebViewDelegate *self = del;
	[self release];
}

static int delegateLoop(void * del, bool blocking) {
	WebViewDelegate *self = del;
    return [self loop:blocking];
}

static int delegateEvalNoFree(void * del, const char *js) {
	WebViewDelegate *self = del;
	return [self eval:[NSString stringWithUTF8String:js]];
}

static int delegateEval(void * del, const char *js) {
	int ret = delegateEvalNoFree(del, js);
	free((void *)js);
	return ret;
}

static int delegateInjectCSS(void * del, const char *css) {
	int ret = injectCSS(del, css, delegateEvalNoFree);
	free((void *)css);
	return ret;
}

static void delegateSetTitle(void * del, const char *title) {
	WebViewDelegate *self = del;
	[self setTitle:[NSString stringWithUTF8String:title]];
	free((void *)title);
}

static void delegateSetFullscreen(void * del, bool fullscreen) {
	WebViewDelegate *self = del;
    [self setFullscreen:fullscreen];
}

static void delegateSetColor(void * del, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
	WebViewDelegate *self = del;
	NSColor *color = [NSColor colorWithRed:(float)r/255.0 green:(float)g/255.0 blue:(float)b/255.0 alpha:(float)a/255.0];
    [self setColor:color];
}

static void delegateDialog(void * del, enum webview_dialog_type type, int flags, const char *title, const char *arg, char *result, size_t resultsz) {
	WebViewDelegate *self = del;
    NSString *_title = [NSString stringWithUTF8String:title];
    NSString *_arg = [NSString stringWithUTF8String:arg];
    NSString *nsresult = [self dialog:type flags:flags title:_title arg:_arg];
	strlcpy(result, nsresult.UTF8String, resultsz);
	free((void *)title);
	free((void *)arg);
}

static void delegateStop(void * del) {
	WebViewDelegate *self = del;
    [self stop];
}

static void appTerminate() {
    NSApplication *app = NSApplication.sharedApplication;
    [app terminate:app];
}

static void dispatch() {
    dispatch_async_f(dispatch_get_main_queue(), NULL, dispatchCallback);
}
*/
import "C"
import (
	"fmt"
	"runtime"
	"sync"
	"unsafe"
)

func debug(a ...interface{}) {
	C.nslog(C.CString(fmt.Sprint(a...)))
}

func debugf(format string, a ...interface{}) {
	C.nslog(C.CString(fmt.Sprintf(format, a...)))
}

var dispatchChain = struct {
	sync.Mutex
	fns []func()
}{}

//export dispatchCallback
func dispatchCallback(unsafe.Pointer) {
	dispatchChain.Lock()
	fns := dispatchChain.fns
	dispatchChain.fns = nil
	dispatchChain.Unlock()

	if len(fns) == 0 {
		return
	}

	for _, fn := range fns {
		fn()
	}
}

type webview struct {
	mu        sync.RWMutex
	delegate  unsafe.Pointer
	callbacks []ExternalInvokeCallbackFunc
}

func newWebView(title, url string, width, height int, resizable, debug bool) *webview {
	w := new(webview)
	w.delegate = C.newDelegate(unsafe.Pointer(w), C.CString(title), C.CString(url), C.int(width), C.int(height), C.bool(resizable), C.bool(debug))
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

func (w *webview) Loop(blocking bool) bool {
	r := C.delegateLoop(w.delegate, C.bool(blocking))
	return r == 0
}

func (w *webview) Eval(js string) error {
	ret := C.delegateEval(w.delegate, C.CString(js))

	switch ret {
	case -1:
		return fmt.Errorf("evaluation failed")
	}

	return nil
}

func (w *webview) SetTitle(title string) {
	C.delegateSetTitle(w.delegate, C.CString(title))
}

func (w *webview) SetFullscreen(fullscreen bool) {
	C.delegateSetFullscreen(w.delegate, C.bool(fullscreen))
}

func (w *webview) SetColor(r, g, b, a uint8) {
	C.delegateSetColor(w.delegate, C.uint8_t(r), C.uint8_t(g), C.uint8_t(b), C.uint8_t(a))
}

func (w *webview) Dialog(typ DialogType, flags int, title, arg string) string {
	const maxPath = 4096
	result := (*C.char)(C.calloc((C.size_t)(unsafe.Sizeof((*C.char)(nil))), (C.size_t)(maxPath)))
	defer C.free(unsafe.Pointer(result))

	C.delegateDialog(w.delegate, C.enum_webview_dialog_type(typ), C.int(flags), C.CString(title), C.CString(arg), result, C.size_t(maxPath))
	return C.GoString(result)
}

func (w *webview) Terminate() {
	C.delegateStop(w.delegate)
}

func (w *webview) Exit() {
	C.appTerminate()
}

func (w *webview) Dispatch(fn func()) {
	dispatchChain.Lock()
	dispatchChain.fns = append(dispatchChain.fns, fn)
	dispatchChain.Unlock()
	C.dispatch()
}

func (w *webview) InjectCSS(css string) {
	C.delegateInjectCSS(w.delegate, C.CString(css))
}
