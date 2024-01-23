package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"reflect"
	"strconv"
	"strings"
	"unicode"

	"github.com/samber/lo"
)

type jsonTagNotFoundError struct {
	tag string
}

func (e *jsonTagNotFoundError) Error() string {
	return fmt.Sprintf("failed to lookup json tag in %s", e.tag)
}

func eprintf(format string, args ...interface{}) {
	if _, err := fmt.Fprintf(os.Stderr, format, args...); err != nil {
		panic(err)
	}
}

func renameType(x string) string {
	switch x {
	case "int":
		return "i32"
	case "int8":
		return "i8"
	case "int16":
		return "i16"
	case "int32":
		return "i32"
	case "int64":
		return "i64"
	case "uint":
		return "u32"
	case "uint8":
		return "u8"
	case "uint16":
		return "u16"
	case "uint32":
		return "u32"
	case "uint64":
		return "u64"
	case "float32":
		return "f32"
	case "float64":
		return "f64"
	case "string":
		return "String"
	case "bool":
		return "bool"
	case "any":
		return "serde_json::Value"
	default:
		runes := []rune(x)
		if runes[0] >= 'a' && runes[0] <= 'z' {
			runes[0] = unicode.ToUpper(runes[0])
		}
		return string(runes)
	}
}

func renderTypeExpr(x ast.Expr) (string, error) {
	if x == nil {
		return "", fmt.Errorf("nil type")
	}
	switch x := x.(type) {
	case *ast.Ident:
		return renameType(x.Name), nil
	case *ast.StarExpr:
		ref, err := renderTypeExpr(x.X)
		if err != nil {
			return "", err
		}
		// boxed
		return fmt.Sprintf("Box<%s>", ref), nil
	case *ast.ArrayType:
		inner, err := renderTypeExpr(x.Elt)
		if err != nil {
			return "", err
		}
		if x.Len == nil {
			return fmt.Sprintf("Vec<%s>", inner), nil
		} else {
			ln, err := renderTypeExpr(x.Len)
			if err != nil {
				return "", err
			}
			return fmt.Sprintf("[%s; %s]", inner, ln), nil
		}
	case *ast.MapType:
		key, err := renderTypeExpr(x.Key)
		if err != nil {
			return "", err
		}
		value, err := renderTypeExpr(x.Value)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("HashMap<%s, %s>", key, value), nil
	case *ast.SelectorExpr:
		parent, ok := x.X.(*ast.Ident)
		if !ok {
			return "", fmt.Errorf("unknown selector %T", x.X)
		}
		sel, err := renderTypeExpr(x.Sel)
		if err != nil {
			return "", err
		}
		if parent.Name == "time" && sel == "Time" {
			return "String", nil
		}
		return "", fmt.Errorf("unknown selector %s.%s", parent.Name, sel)
	default:
		return "", fmt.Errorf("unknown type %T", x)
	}
}

func renderStructComment(comments, doccomments *ast.CommentGroup) string {
	list := []string{}
	if comments != nil && comments.List != nil {
		comments := lo.Map(comments.List, func(c *ast.Comment, _ int) string {
			return fmt.Sprintf("/%s", c.Text)
		})
		list = append(list, comments...)
	}
	if doccomments != nil && doccomments.List != nil {
		doccomments := lo.Map(doccomments.List, func(c *ast.Comment, _ int) string {
			return fmt.Sprintf("/// %s", c.Text)
		})
		list = append(list, doccomments...)
	}
	return strings.Join(list, "\n")
}

// https://zenn.dev/ohnishi/articles/1c84376fe89f70888b9c
func toSnakeCase(s string) string {
	b := &strings.Builder{}
	for i, r := range s {
		if i == 0 {
			b.WriteRune(unicode.ToLower(r))
			continue
		}
		if unicode.IsUpper(r) {
			b.WriteRune('_')
			b.WriteRune(unicode.ToLower(r))
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}

func renameField(x string) string {
	switch x {
	case "type", "Type":
		return "r#type"
	case "ref", "Ref":
		return "r#ref"
	default:
		replaced := strings.ReplaceAll(x, "_", "")
		replaced = strings.ReplaceAll(replaced, "ID", "Id")
		replaced = strings.ReplaceAll(replaced, "URL", "Url")
		replaced = strings.ReplaceAll(replaced, "HTML", "Html")
		replaced = strings.ReplaceAll(replaced, "SHA", "Sha")
		replaced = strings.ReplaceAll(replaced, "SSH", "Ssh")
		return toSnakeCase(replaced)
	}
}

func renderEmbedTypeExprField(x ast.Expr) (string, error) {
	if x == nil {
		return "", fmt.Errorf("nil type")
	}
	switch x := x.(type) {
	case *ast.Ident:
		return renameField(x.Name), nil
	default:
		return "", fmt.Errorf("unknown type %T", x)
	}
}

func extractJsonTagValue(x *ast.BasicLit) (string, error) {
	if x == nil {
		return "", fmt.Errorf("nil tag")
	}
	if x.Kind != token.STRING {
		return "", fmt.Errorf("unknown tag %s", x.Value)
	}
	tag, err := strconv.Unquote(x.Value)
	if err != nil {
		return "", fmt.Errorf("failed to unquote tag %s: %s", x.Value, err)
	}
	stag := reflect.StructTag(tag)
	result, ok := stag.Lookup("json")
	if !ok {
		return "", &jsonTagNotFoundError{x.Value}
	}
	return result, nil
}

func renderField(x *ast.Field) (string, error) {
	renderedType, err := renderTypeExpr(x.Type)
	if err != nil {
		return "", fmt.Errorf("failed to render field %s: %s", x.Names[0].Name, err)
	}

	if x.Names == nil || len(x.Names) == 0 {
		renderedField, err := renderEmbedTypeExprField(x.Type)
		if err != nil {
			return "", fmt.Errorf("failed to render field %s: %s", x.Names[0].Name, err)
		}
		return fmt.Sprintf("    pub %s: %s,", renderedField, renderedType), nil
	}

	name := renameField(x.Names[0].Name)
	var tag *string
	if tagValue, err := extractJsonTagValue(x.Tag); err != nil {
		if _, ok := err.(*jsonTagNotFoundError); !ok {
			return "", fmt.Errorf("failed to render field %s: %s", x.Names[0].Name, err)
		}
	} else {
		if tagValue == "-" {
			return fmt.Sprintf("    // field %s is omitted", name), nil
		}
		splitted := strings.Split(tagValue, ",")
		omitempty := lo.Contains(splitted, "omitempty")
		if omitempty {
			tagValue = strings.Join(lo.Filter(splitted, func(s string, _ int) bool {
				return s != "omitempty"
			}), ",")
			renderedType = fmt.Sprintf("Option<%s>", renderedType)
		}
		tag = &tagValue
	}
	if name == "self" {
		name = "self_"
		if tag == nil {
			slf := "self"
			tag = &slf
		}
	}
	prefix := "#[serde(default)]\n    "
	if tag != nil {
		prefix = fmt.Sprintf("#[serde(default, rename = \"%s\")]\n    ", *tag)
	}
	return fmt.Sprintf("    %spub %s: %s,", prefix, name, renderedType), nil
}

func renderStructInner(x *ast.StructType) string {
	fields := lo.FilterMap(x.Fields.List, func(f *ast.Field, _ int) (string, bool) {
		field, err := renderField(f)
		if err != nil {
			eprintf("failed to render field: %s\n", err)
			return "", false
		}
		return field, true
	})
	return strings.Join(fields, "\n")
}

func renderTypeSpec(x *ast.TypeSpec) string {
	comments := renderStructComment(x.Comment, x.Doc)
	if s, ok := x.Type.(*ast.StructType); ok {
		name := renameType(x.Name.Name)
		inner := renderStructInner(s)
		derives := "#[derive(Debug, Clone, PartialEq, Default, serde::Serialize, serde::Deserialize)]"
		ret := fmt.Sprintf("%s\n%s\npub struct %s {\n%s\n}\n", comments, derives, name, inner)
		return ret
	}
	name := renameType(x.Name.Name)
	alias, err := renderTypeExpr(x.Type)
	if err != nil {
		e := err.Error()
		eprintf("failed to render type %s: %s\n", name, e)
		return ""
	}
	ret := fmt.Sprintf("%s\npub type %s = %s;", comments, name, alias)
	return ret
}

func go2rsFile(path string) {
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, path, nil, parser.ParseComments)
	if err != nil {
		fmt.Println(err)
		return
	}
	lastComments := []*ast.Comment{}
	ast.Inspect(f, func(n ast.Node) bool {
		if n == nil {
			return true
		}
		switch x := n.(type) {
		case *ast.Comment:
			lastComments = append(lastComments, x)
		case *ast.TypeSpec:
			if x == nil {
				return true
			}
			if len(lastComments) > 0 {
				x.Comment = &ast.CommentGroup{List: lastComments}
			}
			fmt.Println(renderTypeSpec(x))
			lastComments = []*ast.Comment{}
		default:
			lastComments = []*ast.Comment{}
		}
		return true
	})
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: go2rs [<path>...]")
		return
	}
	for _, path := range os.Args[1:] {
		go2rsFile(path)
	}
}
