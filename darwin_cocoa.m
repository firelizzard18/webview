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

static void createMenuItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSEventModifierFlags modifiers) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    if (modifiers) item.keyEquivalentModifierMask = modifiers;
    [item autorelease];
    [menu addItem:item];
}

@implementation WebViewDelegate
- (id) initWithContext:(void *)context url:(NSURL *)url title:(NSString *)title width:(int)width height:(int)height resizable:(BOOL)resizable debug:(BOOL)debug
{
    if (!(self = [super init]))
        return nil;

    _context = context;
    _shouldExit = NO;
    _pool = [NSAutoreleasePool new];

    // ensure the shared instance is created
    [NSApplication sharedApplication];

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

    CGRect r = CGRectMake(0, 0, width, height);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    if (resizable)
        style |= NSWindowStyleMaskResizable;

    _window = [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];

    _window.title = title;
    _window.delegate = self;

    [_window autorelease];
    [_window center];

    _webview = [[WKWebView alloc] initWithFrame:r configuration:config];
    _webview.UIDelegate = self;
    _webview.navigationDelegate = self;

    [_webview loadRequest:[NSURLRequest requestWithURL:url]];
    _webview.autoresizesSubviews = YES;
    _webview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_window.contentView addSubview:_webview];
    [_window orderFrontRegardless];

    NSApplication.sharedApplication.activationPolicy = NSApplicationActivationPolicyRegular;
    [NSApplication.sharedApplication finishLaunching];
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];

    NSMenu *menubar = [[NSMenu alloc] initWithTitle:@""];
    [menubar autorelease];

    NSString *appName = NSProcessInfo.processInfo.processName;

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:appName action:NULL keyEquivalent:@""];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
    [appMenu autorelease];

    appMenuItem.submenu = appMenu;
    [menubar addItem:appMenuItem];

    createMenuItem(appMenu, [@"Hide " stringByAppendingString:appName], @selector(hide:), @"h", NSEventModifierFlagCommand);
    createMenuItem(appMenu, @"Hide Others", @selector(hideOtherApplications:), @"h", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    createMenuItem(appMenu, @"Show All", @selector(unhideAllApplications:), @"", 0);

    [appMenu addItem:NSMenuItem.separatorItem];

    createMenuItem(appMenu, [@"Quit " stringByAppendingString:appName], @selector(terminate:), @"q", NSEventModifierFlagCommand);

    NSApplication.sharedApplication.mainMenu = menubar;

    return self;
}

- (void) windowWillClose:(NSNotification *)notification
{
    _shouldExit = YES;
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

- (int) loop:(BOOL)blocking
{
    NSDate *until = blocking ? NSDate.distantFuture : NSDate.distantPast;
    NSEvent *event = [NSApplication.sharedApplication nextEventMatchingMask:NSEventMaskAny untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
    if (event)
        [NSApplication.sharedApplication sendEvent:event];

    return _shouldExit;
}

- (int) eval:(NSString *)js
{
    [_webview evaluateJavaScript:js completionHandler:NULL];
    return 0;
}

- (void) setTitle:(NSString *)title
{
    _window.title = title;
}

- (void) setFullscreen:(BOOL)fullscreen
{
    if ((_window.styleMask & NSWindowStyleMaskFullScreen) ^ fullscreen)
        [_window toggleFullScreen:NULL];
}

- (void) setColor:(NSColor *)color
{
    _window.backgroundColor = color;
    if (0.5 >= (color.redComponent * 0.299) + (color.greenComponent * 0.587) + (color.blueComponent * 0.114)) {
        _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    } else {
        _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantLight];
    }

    _window.opaque = NO;
    _window.titlebarAppearsTransparent = YES;
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

        [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
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

        [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
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

- (void) stop
{
    _shouldExit = YES;
}
@end
