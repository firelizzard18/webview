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

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

void freeSchemeHandler(void * context);
void startURLSchemeTask(void * context, void * webview, void * task);
void stopURLSchemeTask(void * context, void * webview, void * task);

@interface SchemeHandler : NSObject <WKURLSchemeHandler>
@property (readonly) void * context;
@end

@implementation SchemeHandler
- (id) initWithContext:(void *)context
{
    if (!(self = [super init]))
        return nil;

    _context = context;
    return self;
}

- (void) dealloc
{
    freeSchemeHandler(self.context);
    [super dealloc];
}

- (void) webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    startURLSchemeTask(self.context, webView, urlSchemeTask);
}

- (void) webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    stopURLSchemeTask(self.context, webView, urlSchemeTask);
}
@end

void addSchemeHandler(void * config, void * context, void * scheme)
{
    SchemeHandler * handler = [[SchemeHandler alloc] initWithContext:context];
    [(WKWebViewConfiguration *)config setURLSchemeHandler:handler forURLScheme:scheme];
}

void schemeTaskFinished(id<WKURLSchemeTask> task) {
	@try {
		[task didFinish];
	}
	@catch (NSException * e) {
		NSLog(@"Exception while marking webview task as complete: %@", e);
	}
}

void schemeTaskFailed(id<WKURLSchemeTask> task, NSString * error) {
	NSError * err = [[NSError alloc] initWithDomain:@"GoSchemeHandler" code:1 userInfo:@{@"Message": (NSString *)error}];
	@try {
		[task didFailWithError:err];
	}
	@catch (NSException * e) {
		NSLog(@"Exception while marking webview task as failed: %@", e);
	}
}

void schemeTaskRespond(id<WKURLSchemeTask> task, NSInteger code, NSDictionary * header) {
	NSHTTPURLResponse * res = [[NSHTTPURLResponse alloc] initWithURL:task.request.URL statusCode:code HTTPVersion:@"HTTP/1.1" headerFields:header];
	@try {
		[task didReceiveResponse:res];
	}
	@catch (NSException * e) {
		NSLog(@"Exception while responding to webview task: %@", e);
	}
}

void schemeTaskWrite(id<WKURLSchemeTask> task, NSData * data) {
	@try {
		[task didReceiveData:data];
	}
	@catch (NSException * e) {
		NSLog(@"Exception while writing to webview task response: %@", e);
	}
}