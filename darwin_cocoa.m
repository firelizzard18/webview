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

#import "webview.h"
#import "darwin_cocoa.h"

extern void webviewCallback(void *, const char *);
extern void javaScriptEvaluationComplete(void * ref, const char * description, const char * message, const char * url, int line, int col);

@implementation WebViewDelegate
- (id) initWithContext:(void *)context window:(NSWindow *)window url:(NSURL *)url debug:(BOOL)debug
{
    if (!(self = [super init]))
        return nil;

    _context = context;
    _window = window;

    WKPreferences *wkprefs = [WKPreferences new];
    if (debug) [wkprefs _setDeveloperExtrasEnabled:YES];

    WKUserContentController *userController = [WKUserContentController new];
    [userController addScriptMessageHandler:self name:@"invoke"];

    /***
     In order to maintain compatibility with the other 'webviews' we need to
     override window.external.invoke to call
     webkit.messageHandlers.invoke.postMessage
     ***/

    NSString *src = @"window.external = this; invoke = function(arg){ webkit.messageHandlers.invoke.postMessage(arg); };";
    [userController addUserScript:[[WKUserScript alloc] initWithSource:src injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    WKProcessPool *processPool = config.processPool;
    [processPool _setDownloadDelegate:self];
    config.processPool = processPool;
    config.userContentController = userController;
    config.preferences = wkprefs;

    _webview = [[WKWebView alloc] initWithFrame:[window contentRectForFrameRect:window.frame] configuration:config];
    _webview.UIDelegate = self;
    _webview.navigationDelegate = self;

    [_webview loadRequest:[NSURLRequest requestWithURL:url]];
    _webview.autoresizesSubviews = YES;
    _webview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [window.contentView addSubview:_webview];

    return self;
}

- (void) dealloc
{
    [_webview release];
    [super dealloc];
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

- (void) evaluateJavaScript:(NSString *)js completionHandler:(void *)handler
{
    [_webview evaluateJavaScript:js completionHandler:^(id _, NSError *error) {
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

- (NSString *) dialog:(enum webview_dialog_type)type flags:(int)flags title:(NSString *)title arg:(NSString *)arg
{
    if (type == WEBVIEW_DIALOG_TYPE_OPEN) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = !(flags & WEBVIEW_DIALOG_FLAG_DIRECTORY);
        panel.canChooseDirectories = !!(flags & WEBVIEW_DIALOG_FLAG_DIRECTORY);
        panel.resolvesAliases = NO;
        panel.allowsMultipleSelection = NO;

        panel.canCreateDirectories = YES;
        panel.showsHiddenFiles = YES;
        panel.extensionHidden = NO;
        panel.canSelectHiddenExtension = NO;
        panel.treatsFilePackagesAsDirectories = YES;

        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
            [NSApplication.sharedApplication stopModalWithCode:result];
        }];

        if ([NSApplication.sharedApplication runModalForWindow:panel] == NSModalResponseOK) {
            return panel.URL.path;
        }
        return nil;

    }

    if (type == WEBVIEW_DIALOG_TYPE_SAVE) {
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.canCreateDirectories = YES;
        panel.showsHiddenFiles = YES;
        panel.extensionHidden = NO;
        panel.canSelectHiddenExtension = NO;
        panel.treatsFilePackagesAsDirectories = YES;

        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
            [NSApplication.sharedApplication stopModalWithCode:result];
        }];

        if ([NSApplication.sharedApplication runModalForWindow:panel] == NSModalResponseOK) {
            return panel.URL.path;
        }
        return nil;
    }

    if (type == WEBVIEW_DIALOG_TYPE_ALERT) {
        NSAlert *alert = [NSAlert new];

        switch (flags & WEBVIEW_DIALOG_FLAG_ALERT_MASK) {
        case WEBVIEW_DIALOG_FLAG_INFO:
            alert.alertStyle = NSAlertStyleInformational;
            break;

        case WEBVIEW_DIALOG_FLAG_WARNING:
            printf("Warning\n");
            alert.alertStyle = NSAlertStyleWarning;
            break;

        case WEBVIEW_DIALOG_FLAG_ERROR:
            printf("Error\n");
            alert.alertStyle = NSAlertStyleCritical;
            break;
        }

        alert.showsHelp = NO;
        alert.showsSuppressionButton = NO;
        alert.messageText = title;
        alert.informativeText = arg;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        return nil;
    }

    return nil;
}
@end
