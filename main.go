package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strings"
	"unicode"

	"github.com/samber/lo"
)

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
	default:
		return x
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
		// remove reference
		return ref, nil
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
		parent, err := renderTypeExpr(x.X)
		if err != nil {
			return "", err
		}
		t, err := renderTypeExpr(x.Sel)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("%s::%s", parent, t), nil
	default:
		return "", fmt.Errorf("unknown type %T", x)
	}
}

func renderStructComment(x *ast.CommentGroup) string {
	if x == nil {
		return ""
	}
	return strings.Join(lo.Map(x.List, func(c *ast.Comment, _ int) string {
		return fmt.Sprintf("/// %s", c.Text)
	}), "\n")
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
	default:
		replaced := strings.ReplaceAll(x, "_", "")
		replaced = strings.ReplaceAll(replaced, "ID", "Id")
		replaced = strings.ReplaceAll(replaced, "URL", "Url")
		return toSnakeCase(replaced)
	}
}

func renderStructInner(x *ast.StructType) string {
	fields := lo.Map(x.Fields.List, func(f *ast.Field, _ int) string {
		names := strings.Join(lo.Map(f.Names, func(n *ast.Ident, _ int) string {
			return renameField(n.Name)
		}), " ")
		renderedType, err := renderTypeExpr(f.Type)
		if err != nil {
			return err.Error()
		}
		return fmt.Sprintf("    pub %s: %s,", names, renderedType)
	})
	return strings.Join(fields, "\n")
}

func renderTypeSpec(x *ast.TypeSpec) string {
	comments := renderStructComment(x.Doc)
	if s, ok := x.Type.(*ast.StructType); ok {
		inner := renderStructInner(s)
		derives := "#[derive(Debug, Clone, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]"
		ret := fmt.Sprintf("%s\n%s\npub struct %s {\n%s\n}", comments, derives, x.Name.Name, inner)
		return ret
	}
	alias, err := renderTypeExpr(x.Type)
	if err != nil {
		e := err.Error()
		if _, err := fmt.Fprintf(os.Stderr, "failed to render type %s: %s", x.Name.Name, e); err != nil {
			panic(err)
		}
		return ""
	}
	ret := fmt.Sprintf("%s\npub type %s = %s;", comments, x.Name.Name, alias)
	return ret
}

func go2rsFile(path string) {
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, path, nil, 0)
	if err != nil {
		fmt.Println(err)
		return
	}
	ast.Inspect(f, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.TypeSpec:
			if x == nil {
				return true
			}
			fmt.Println(renderTypeSpec(x))
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