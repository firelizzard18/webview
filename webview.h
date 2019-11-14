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

#ifndef __WEBVIEW_H
#define __WEBVIEW_H

struct webview;
enum webview_dialog_type;

#ifdef DARWIN
#import "webview_darwin.h"
typedef WebViewDelegate* webkit_priv;
#else
#error "Unsupported OS"
#endif

typedef void (*webview_external_invoke_cb_t)(struct webview *w, const char *arg);

struct webview {
    const char *url;
    const char *title;
    int width;
    int height;
    int resizable;
    int debug;
    webview_external_invoke_cb_t external_invoke_cb;
    void *userdata;
    webkit_priv priv;
};

enum webview_dialog_type {
    WEBVIEW_DIALOG_TYPE_OPEN = 0,
    WEBVIEW_DIALOG_TYPE_SAVE = 1,
    WEBVIEW_DIALOG_TYPE_ALERT = 2
};

#define WEBVIEW_DIALOG_FLAG_FILE (0 << 0)
#define WEBVIEW_DIALOG_FLAG_DIRECTORY (1 << 0)

#define WEBVIEW_DIALOG_FLAG_INFO (1 << 1)
#define WEBVIEW_DIALOG_FLAG_WARNING (2 << 1)
#define WEBVIEW_DIALOG_FLAG_ERROR (3 << 1)
#define WEBVIEW_DIALOG_FLAG_ALERT_MASK (3 << 1)

typedef void (*webview_dispatch_fn)(struct webview *w, void *arg);

struct webview_dispatch_arg {
    webview_dispatch_fn fn;
    struct webview *w;
    void *arg;
};

#define DEFAULT_URL                                                              \
    "data:text/"                                                                 \
    "html,%3C%21DOCTYPE%20html%3E%0A%3Chtml%20lang=%22en%22%3E%0A%3Chead%3E%"    \
    "3Cmeta%20charset=%22utf-8%22%3E%3Cmeta%20http-equiv=%22X-UA-Compatible%22%" \
    "20content=%22IE=edge%22%3E%3C%2Fhead%3E%0A%3Cbody%3E%3Cdiv%20id=%22app%22%" \
    "3E%3C%2Fdiv%3E%3Cscript%20type=%22text%2Fjavascript%22%3E%3C%2Fscript%3E%"  \
    "3C%2Fbody%3E%0A%3C%2Fhtml%3E"

#define CSS_INJECT_FUNCTION                                                      \
    "(function(e){var "                                                          \
    "t=document.createElement('style'),d=document.head||document."               \
    "getElementsByTagName('head')[0];t.setAttribute('type','text/"               \
    "css'),t.styleSheet?t.styleSheet.cssText=e:t.appendChild(document."          \
    "createTextNode(e)),d.appendChild(t)})"

int webview(const char *title, const char *url, int width, int height, int resizable);
int webview_init(struct webview *w);
int webview_loop(struct webview *w, int blocking);
int webview_eval(struct webview *w, const char *js);
int webview_inject_css(struct webview *w, const char *css);
void webview_set_title(struct webview *w, const char *title);
void webview_set_fullscreen(struct webview *w, int fullscreen);
void webview_set_color(struct webview *w, uint8_t r, uint8_t g,
                                   uint8_t b, uint8_t a);
void webview_dialog(struct webview *w,
                                enum webview_dialog_type dlgtype, int flags,
                                const char *title, const char *arg,
                                char *result, size_t resultsz);
void webview_dispatch(struct webview *w, webview_dispatch_fn fn,
                                  void *arg);
void webview_terminate(struct webview *w);
void webview_exit(struct webview *w);
void webview_debug(const char *format, ...);
void webview_print_log(const char *s);

#endif