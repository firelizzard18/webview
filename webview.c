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

#include "webview.h"

int jsEncode(const char *s, char *esc, size_t n) {
	int r = 1; /* At least one byte for trailing zero */
	for (; *s; s++) {
		const unsigned char c = *s;
		if (c >= 0x20 && c < 0x80 && strchr("<>\\'\"", c) == NULL) {
			if (n > 0) {
				*esc++ = c;
				n--;
			}
			r++;
		} else {
			if (n > 0) {
				snprintf(esc, n, "\\x%02x", (int)c);
				esc += 4;
				n -= 4;
			}
			r += 4;
		}
	}
	return r;
}

int injectCSS(void *private, const char *css, int (*eval)(void *, const char *)) {
	int n = jsEncode(css, NULL, 0);
	char *esc = (char *)calloc(1, sizeof(CSS_INJECT_FUNCTION) + n + 4);
	if (esc == NULL) {
		return -1;
	}
	char *js = (char *)calloc(1, n);
	jsEncode(css, js, n);
	snprintf(esc, sizeof(CSS_INJECT_FUNCTION) + n + 4, "%s(\"%s\")", CSS_INJECT_FUNCTION, js);
	int r = eval(private, esc);
	free(js);
	free(esc);
	return r;
}
