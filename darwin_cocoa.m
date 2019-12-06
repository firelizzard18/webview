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

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <CoreGraphics/CoreGraphics.h>

extern void webviewCallback(void *, const char *);
extern void javaScriptEvaluationComplete(void * ref, const char * description, const char * message, const char * url, int line, int col);

// https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownload.h
@class _WKDownload;

// https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownloadDelegate.h
// https://github.com/WebKit/webkit/blob/master/Tools/TestWebKitAPI/Tests/WebKitCocoa/Download.mm
@protocol WKDownloadDelegate
@optional
- (void)_downloadDidStart:(_WKDownload *)download;
- (void)_download:(_WKDownload *)download didReceiveServerRedirectToURL:(NSURL *)url;
- (void)_download:(_WKDownload *)download didReceiveResponse:(NSURLResponse *)response;
- (void)_download:(_WKDownload *)download didReceiveData:(uint64_t)length;
- (void)_download:(_WKDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename completionHandler:(void (^)(BOOL allowOverwrite, NSString *destination))completionHandler;
- (void)_downloadDidFinish:(_WKDownload *)download;
- (void)_download:(_WKDownload *)download didFailWithError:(NSError *)error;
- (void)_downloadDidCancel:(_WKDownload *)download;
- (void)_download:(_WKDownload *)download didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential*))completionHandler;
- (void)_download:(_WKDownload *)download didCreateDestination:(NSString *)destination;
- (void)_downloadProcessDidCrash:(_WKDownload *)download;
- (BOOL)_download:(_WKDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)MIMEType;
@end

enum webview_dialog_type;

@interface WebViewDelegate : NSObject <WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate>
@property (readonly, assign) NSWindow * window;
@property (readonly, assign) void * context;
@end

@implementation WebViewDelegate
- (id) initWithContext:(void *)context window:(NSWindow *)window
{
    if (!(self = [super init]))
        return nil;

    _context = context;
    _window = window;

    return self;
}

- (void) userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    webviewCallback(_context, ((NSString *)message.body).UTF8String);
}

- (void) _download:(_WKDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename completionHandler:(void (^)(BOOL allowOverwrite, NSString *destination))completionHandler
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.nameFieldStringValue = filename;

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            completionHandler(YES, panel.URL.path);
        } else {
            completionHandler(NO, nil);
        }
    }];
}

- (void) _download:(_WKDownload *)download didFailWithError:(NSError *)error
{
    NSLog(@"%s\n", error.localizedDescription.UTF8String);
}

- (void) webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> *URLs))completionHandler
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];

    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    panel.canChooseFiles = YES;

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            completionHandler(panel.URLs);
        } else {
            completionHandler(nil);
        }
    }];
}

- (void) webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    NSAlert *alert = [NSAlert new];

    alert.icon = [NSImage imageNamed:@"NSCaution"];
    alert.showsHelp = NO;
    alert.informativeText = message;

    [alert runModal];
    [alert release];
    completionHandler();
}

- (void) webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler
{
    NSAlert *alert = [NSAlert new];

    alert.icon = [NSImage imageNamed:@"NSCaution"];
    alert.showsHelp = NO;
    alert.informativeText = message;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        completionHandler(YES);
    } else {
        completionHandler(NO);
    }
    [alert release];
}

- (void) webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
    // if (navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyAllow);
    // } else {
    //     decisionHandler(WKNavigationActionPolicyDownload);
    // }
}
@end

WKWebView * newWebView(void * context, WKWebViewConfiguration * config, NSWindow * window) {
    NSString * src = @"window.external = this; invoke = function(arg){ webkit.messageHandlers.invoke.postMessage(arg); };";
    WKUserScript * script = [[WKUserScript alloc] initWithSource:src injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [config.userContentController addUserScript:script];
    [script release];

    WebViewDelegate * del = [[WebViewDelegate alloc] initWithContext:context window:window];

    [config.userContentController addScriptMessageHandler:del name:@"invoke"];
    [config.processPool setValue:del forKey:@"downloadDelegate"];

    WKWebView * webView = [[WKWebView alloc] initWithFrame:[window contentRectForFrameRect:window.frame] configuration:config];
    webView.UIDelegate = del;
    webView.navigationDelegate = del;
    webView.autoresizesSubviews = YES;
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [window.contentView addSubview:webView];

    return webView;
}

void evaluateJavaScript(WKWebView * self, NSString * js, void * handler) {
    [self evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (!error) {
            javaScriptEvaluationComplete(handler, NULL, NULL, NULL, -1, -1);
            return;
        }

        NSString * message = error.userInfo[@"WKJavaScriptExceptionMessage"];
        NSURL * url = error.userInfo[@"WKJavaScriptExceptionSourceURL"];
        NSNumber * line = error.userInfo[@"WKJavaScriptExceptionLineNumber"];
        NSNumber * col = error.userInfo[@"WKJavaScriptExceptionColumnNumber"];
        javaScriptEvaluationComplete(handler, error.localizedDescription.UTF8String, message.UTF8String, url.description.UTF8String, line.integerValue, col.integerValue);
    }];
}