/*
 * MIT License
 *
 * Copyright (c) 2017 Serge Zaitsev
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

#ifndef DARWIN
#define DARWIN
#endif

#import "webview.h"

static void createMenuItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSEventModifierFlags modifiers) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    if (modifiers) item.keyEquivalentModifierMask = modifiers;
    [item autorelease];
    [menu addItem:item];
}

@implementation WebViewDelegate
- (id) initWithPublic:(struct webview *)w
{
    if (!(self = [super init]))
        return nil;

    _shouldExit = NO;
    _pub = w;
    _pool = [NSAutoreleasePool new];

    // ensure the shared instance is created
    [NSApplication sharedApplication];

    WKPreferences *wkprefs = [WKPreferences new];
    [wkprefs enableDevExtras];
    // [wkprefs setValue:[NSNumber numberWithBool:w->debug] forKey:@"developerExtrasEnabled"];

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

    CGRect r = CGRectMake(0, 0, w->width, w->height);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    if (w->resizable)
        style |= NSWindowStyleMaskResizable;

    _window = [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];

    _window.title = [NSString stringWithUTF8String:w->title];
    _window.delegate = self;

    [_window autorelease];
    [_window center];

    _webview = [[WKWebView alloc] initWithFrame:r configuration:config];
    _webview.UIDelegate = self;
    _webview.navigationDelegate = self;

    [_webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:w->url]]]];
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

// - (void) dealloc
// {
//     // do stuff
//     [super dealloc];
// }

- (void) windowWillClose:(NSNotification *)notification
{
    webview_terminate(_pub);
}

- (void) userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (!_pub || !_pub->external_invoke_cb)
        return;

    _pub->external_invoke_cb(_pub, ((NSString *)message.body).UTF8String);
}

- (void) _download:(/*_WKDownload **/id)download decideDestinationWithSuggestedFilename:(NSString *)filename completionHandler:(void (^)(BOOL allowOverwrite, NSString *destination))completionHandler
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

- (void) _download:(/*_WKDownload **/id)download didFailWithError:(NSError *)error
{
    printf("%s\n", error.localizedDescription.UTF8String);
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

    // [NSString stringWithUTF8String:kCFRunLoopDefaultMode];
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

- (void) terminate
{
    _shouldExit = YES;
}

- (void) exit
{
    NSApplication *app = NSApplication.sharedApplication;
    [app terminate:app];
}
@end

@implementation WKPreferences (DevExtras)
@dynamic _developerExtrasEnabled;

- (void)enableDevExtras
{
    [self _setDeveloperExtrasEnabled:YES];
}
@end

int webview_init(struct webview *w) {
    w->priv = [[WebViewDelegate alloc] initWithPublic:w];
    return 0;
}

int webview_loop(struct webview *w, int blocking) {
    return [w->priv loop:blocking];
}

int webview_eval(struct webview *w, const char *js) {
    return [w->priv eval:[NSString stringWithUTF8String:js]];
}

void webview_set_title(struct webview *w, const char *title) {
    [w->priv setTitle:[NSString stringWithUTF8String:title]];
}

void webview_set_fullscreen(struct webview *w, int fullscreen) {
    [w->priv setFullscreen:fullscreen];
}

void webview_set_color(struct webview *w, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    [w->priv setColor:[NSColor colorWithRed:(float)r/255.0 green:(float)g/255.0 blue:(float)b/255.0 alpha:(float)a/255.0]];
}

void webview_dialog(struct webview *w,
                                enum webview_dialog_type type, int flags,
                                const char *title, const char *arg,
                                char *result, size_t resultsz) {

    NSString *nsresult = [w->priv dialog:type flags:flags title:[NSString stringWithUTF8String:title] arg:[NSString stringWithUTF8String:arg]];
    strlcpy(result, nsresult.UTF8String, resultsz);
}

static void webview_dispatch_cb(void *arg) {
  struct webview_dispatch_arg *context = (struct webview_dispatch_arg *)arg;
  (context->fn)(context->w, context->arg);
  free(context);
}

void webview_dispatch(struct webview *w, webview_dispatch_fn fn,
                                  void *arg) {
  struct webview_dispatch_arg *context = (struct webview_dispatch_arg *)malloc(
      sizeof(struct webview_dispatch_arg));
  context->w = w;
  context->arg = arg;
  context->fn = fn;
  dispatch_async_f(dispatch_get_main_queue(), context, webview_dispatch_cb);
}

void webview_terminate(struct webview *w) {
    [w->priv terminate];
}

void webview_exit(struct webview *w) {
    [w->priv exit];
}

void webview_print_log(const char *s) { printf("%s\n", s); }