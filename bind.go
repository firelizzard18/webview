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

package webview

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"reflect"
	"text/template"
	"unicode"
)

var bindTmpl = template.Must(template.New("").Parse(`
if (typeof {{.Name}} === 'undefined') {
	{{.Name}} = {};
}
{{ range .Methods }}
{{$.Name}}.{{.JSName}} = function({{.JSArgs}}) {
	window.external.invoke(JSON.stringify({scope: "{{$.Name}}", method: "{{.Name}}", params: [{{.JSArgs}}]}));
};
{{ end }}
`))

type binding struct {
	Value   interface{}
	Name    string
	Methods []methodInfo
}

func newBinding(name string, v interface{}) (*binding, error) {
	methods, err := getMethods(v)
	if err != nil {
		return nil, err
	}
	return &binding{Name: name, Value: v, Methods: methods}, nil
}

func (b *binding) JS() (string, error) {
	js := &bytes.Buffer{}
	err := bindTmpl.Execute(js, b)
	return js.String(), err
}

func (b *binding) Sync() (string, error) {
	js, err := json.Marshal(b.Value)
	if err == nil {
		return fmt.Sprintf("%[1]s.data=%[2]s;if(%[1]s.render){%[1]s.render(%[2]s);}", b.Name, string(js)), nil
	}
	return "", err
}

func (b *binding) Call(js string) bool {
	type rpcCall struct {
		Scope  string        `json:"scope"`
		Method string        `json:"method"`
		Params []interface{} `json:"params"`
	}

	rpc := rpcCall{}
	if err := json.Unmarshal([]byte(js), &rpc); err != nil {
		return false
	}
	if rpc.Scope != b.Name {
		return false
	}
	var mi *methodInfo
	for i := 0; i < len(b.Methods); i++ {
		if b.Methods[i].Name == rpc.Method {
			mi = &b.Methods[i]
			break
		}
	}
	if mi == nil {
		return false
	}
	args := make([]reflect.Value, mi.Arity(), mi.Arity())
	for i := 0; i < mi.Arity(); i++ {
		val := reflect.ValueOf(rpc.Params[i])
		arg := mi.Value.Type().In(i)
		u := reflect.New(arg)
		if b, err := json.Marshal(val.Interface()); err == nil {
			if err = json.Unmarshal(b, u.Interface()); err == nil {
				args[i] = reflect.Indirect(u)
			}
		}
		if !args[i].IsValid() {
			return false
		}
	}
	mi.Value.Call(args)
	return true
}

type methodInfo struct {
	Name  string
	Value reflect.Value
}

func (mi methodInfo) Arity() int { return mi.Value.Type().NumIn() }

func (mi methodInfo) JSName() string {
	r := []rune(mi.Name)
	if len(r) > 0 {
		r[0] = unicode.ToLower(r[0])
	}
	return string(r)
}

func (mi methodInfo) JSArgs() (js string) {
	for i := 0; i < mi.Arity(); i++ {
		if i > 0 {
			js = js + ","
		}
		js = js + fmt.Sprintf("a%d", i)
	}
	return js
}

func getMethods(obj interface{}) ([]methodInfo, error) {
	p := reflect.ValueOf(obj)
	v := reflect.Indirect(p)
	t := reflect.TypeOf(obj)
	if t == nil {
		return nil, errors.New("object can not be nil")
	}
	k := t.Kind()
	if k == reflect.Ptr {
		k = v.Type().Kind()
	}
	if k != reflect.Struct {
		return nil, errors.New("must be a struct or a pointer to a struct")
	}

	methods := []methodInfo{}
	for i := 0; i < t.NumMethod(); i++ {
		method := t.Method(i)
		if !unicode.IsUpper([]rune(method.Name)[0]) {
			continue
		}
		mi := methodInfo{
			Name:  method.Name,
			Value: p.MethodByName(method.Name),
		}
		methods = append(methods, mi)
	}

	return methods, nil
}

// Bind() registers a binding between a given value and a JavaScript object with
// the given name.  A value must be a struct or a struct pointer. All methods
// are available under their camel-case names, starting with a lower-case
// letter, e.g. "FooBar" becomes "fooBar" in JavaScript. Bind() returns a
// function that updates JavaScript object with the current Go value. You only
// need to call it if you change Go value asynchronously.
func (w *WebView) Bind(name string, v interface{}) (sync func(), err error) {
	b, err := newBinding(name, v)
	if err != nil {
		return nil, err
	}
	js, err := b.JS()
	if err != nil {
		return nil, err
	}
	sync = func() {
		if js, err := b.Sync(); err != nil {
			log.Println(err)
		} else {
			w.Evaluate(js)
		}
	}

	w.AddCallback(func(data string) {
		if ok := b.Call(data); ok {
			sync()
		}
	})

	w.Evaluate(js)
	sync()
	return sync, nil
}
