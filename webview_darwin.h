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

#ifndef __WEBVIEW_OS_H
#define __WEBVIEW_OS_H

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <CoreGraphics/CoreGraphics.h>

/***
 _WKDownloadDelegate is an undocumented/private protocol with methods called
 from WKNavigationDelegate
 References:
 https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownload.h
 https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownloadDelegate.h
 https://github.com/WebKit/webkit/blob/master/Tools/TestWebKitAPI/Tests/WebKitCocoa/Download.mm
 ***/

@interface WebViewDelegate : NSObject <NSWindowDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate/*, _WKDownloadDelegate*/>
{
    struct webview *_pub;
    NSAutoreleasePool *_pool;
    NSWindow *_window;
    WKWebView *_webview;
    BOOL _shouldExit;
}

- (id) initWithPublic:(struct webview *)w;

- (int) loop:(BOOL)blocking;
- (int) eval:(NSString *)js;
- (void) setTitle:(NSString *)title;
- (void) setFullscreen:(BOOL)fullscreen;
- (void) setColor:(NSColor *)color;
- (NSString *) dialog:(enum webview_dialog_type)type flags:(int)flags title:(NSString *)title arg:(NSString *)arg;
- (void) terminate;
- (void) exit;
@end

@interface WKPreferences (DevExtras)
@property (nonatomic, setter=_setDeveloperExtrasEnabled:) BOOL _developerExtrasEnabled;
- (void)enableDevExtras;
@end

#endif