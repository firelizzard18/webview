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
// +build !macos10
// +build !macos11
// +build !macos12

package webview

/*
#import <AppKit/AppKit.h>

void addSchemeHandler(void * config, void * context, void * scheme);
void schemeTaskFinished(void * task);
void schemeTaskFailed(void * task, void * error);
void schemeTaskRespond(void * task, NSInteger code, void * header);
void schemeTaskWrite(void * task, void * data);

static void * newDictionary() {
	return [NSMutableDictionary new];
}

static void setHeader(void * dict, void * name, void * value) {
	((NSMutableDictionary *)dict)[(NSString *)name] = (NSString *)value;
}
*/
import "C"

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sync"
	"unsafe"

	"gitlab.com/firelizzard/go-app/cgo"
	"gitlab.com/firelizzard/go-app/objc"
)

var errCancelled = errors.New("request cancelled")

//export freeSchemeHandler
func freeSchemeHandler(context unsafe.Pointer) {
	cgo.Reference(context).Delete()
}

//export startURLSchemeTask
func startURLSchemeTask(ctxptr, webview, task unsafe.Pointer) {
	ctx, cancel := context.WithCancel(context.Background())
	result := &requestResult{cancel: cancel}

	csh := cgo.Reference(ctxptr).Load().(*customSchemeHandler)
	csh.mu.Lock()
	if csh.tasks == nil {
		csh.tasks = map[unsafe.Pointer]*requestResult{}
	}
	csh.tasks[task] = result
	csh.mu.Unlock()

	go func() {
		<-ctx.Done()
		csh.mu.Lock()
		delete(csh.tasks, task)
		csh.mu.Unlock()

		if result.err == errCancelled {
			return
		}

		if result.err == nil {
			C.schemeTaskFinished(task)
		} else {
			err := objc.NSString(result.err.Error())
			defer objc.Release(err)
			C.schemeTaskFailed(task, err)
		}
	}()

	// type responseWriter struct {
	// 	task        unsafe.Pointer
	// 	wroteHeader bool
	// 	header      http.Header
	// }
	go func() {
		defer cancel()
		defer result.Set(nil)

		method := objc.GoString(objc.ValueForKey(task, "request.HTTPMethod"))
		url := objc.GoString(objc.ValueForKey(task, "request.URL.absoluteString"))

		var body io.Reader
		if data := objc.ValueForKey(task, "request.HTTPBody"); data != nil {
			body = bytes.NewBuffer(objc.GoBytes(data))
		} else if stream := objc.ValueForKey(task, "request.HTTPBodyStream"); stream != nil {
			body = objc.GoReader(stream, false)
		}

		req, err := http.NewRequest(method, url, body)
		if err != nil {
			result.Set(fmt.Errorf("failed to convert request: %v", err))
			return
		}

		objc.EnumerateDictionary(objc.ValueForKey(task, "request.allHTTPHeaderFields"), func(k, v unsafe.Pointer) {
			key := objc.GoString(k)
			value := objc.GoString(v)

			prev, _ := req.Header[key]
			req.Header[key] = append(prev, value)
		})

		csh.handler.ServeHTTP(&responseWriter{task: task}, req.WithContext(ctx))
	}()
}

//export stopURLSchemeTask
func stopURLSchemeTask(context, webview, task unsafe.Pointer) {
	csh := cgo.Reference(context).Load().(*customSchemeHandler)

	csh.mu.RLock()
	r, ok := csh.tasks[task]
	csh.mu.RUnlock()

	if ok {
		r.Set(errCancelled)
	}
}

func (s *Settings) AddCustomScheme(scheme string, handler http.Handler) {
	sch := objc.NSString(scheme)
	defer objc.Release(sch)

	csh := &customSchemeHandler{handler: handler}
	C.addSchemeHandler(s.id, cgo.Save(csh).C(), sch)
}

type customSchemeHandler struct {
	handler http.Handler
	mu      sync.RWMutex
	tasks   map[unsafe.Pointer]*requestResult
}

type requestResult struct {
	mu     sync.Mutex
	err    error
	set    bool
	cancel context.CancelFunc
}

func (r *requestResult) Set(err error) {
	r.mu.Lock()
	if r.set {
		r.mu.Unlock()
		return
	}

	r.err, r.set = err, true
	r.cancel()
	r.mu.Unlock()
}

type responseWriter struct {
	task        unsafe.Pointer
	wroteHeader bool
	header      http.Header
}

func (w *responseWriter) Header() http.Header {
	if w.header == nil {
		w.header = http.Header{}
	}
	return w.header
}

// void schemeTaskRespond(void * task, NSInteger code, void * header);
func (w *responseWriter) WriteHeader(statusCode int) {
	if w.wroteHeader {
		return
	}
	w.wroteHeader = true

	headers := C.newDictionary()
	defer objc.Release(headers)

	for key, values := range w.header {
		if len(values) == 0 {
			continue
		}

		k := objc.NSString(key)
		defer objc.Release(k)

		// BUG: how can NSHTTPURLResponse accept multiple values?
		v := objc.NSString(values[0])
		defer objc.Release(v)

		C.setHeader(headers, k, v)
	}

	C.schemeTaskRespond(w.task, C.NSInteger(statusCode), headers)
}

func (w *responseWriter) Write(b []byte) (int, error) {
	w.WriteHeader(http.StatusOK)

	data := objc.NSData(b)
	defer objc.Release(data)

	C.schemeTaskWrite(w.task, data)
	return len(b), nil
}
