package dev.thyexp;

import org.unbescape.html.HtmlEscape;
import org.unbescape.xml.XmlEscape;
import org.unbescape.javascript.JavaScriptEscape;
import org.unbescape.json.JsonEscape;
import org.unbescape.css.CssEscape;
import org.unbescape.java.JavaEscape;
import org.unbescape.csv.CsvEscape;
import org.unbescape.properties.PropertiesEscape;
import org.unbescape.uri.UriEscape;

public class UnbescapeWorkload {

    public static void main(String[] args) {
        String html = "<div class=\"test\">Hello & 'World' éàü</div>";
        String xml  = "<root attr=\"val\">text &amp; more é</root>";
        String js   = "alert(\"hello\\nworld\"); var x = '<test>';";
        String json = "{\"key\": \"val\\nwith\\ttabs & <special>\"}";
        String css  = "content: 'hello \\ world'; color: #abc;";
        String java = "String s = \"hello\\nworld\"; // é";
        String csv  = "field1,\"field,2\",field\"3";
        String prop = "key=value with spaces and \\u00e9 accents";
        String uri  = "http://example.com/path?q=hello world&x=<test>";

        // HTML — loads Html5EscapeSymbolsInitializer + HtmlEscapeSymbols
        HtmlEscape.escapeHtml5(html);
        HtmlEscape.escapeHtml4(html);
        HtmlEscape.unescapeHtml(html);

        // XML — loads Xml10EscapeSymbolsInitializer + Xml11EscapeSymbolsInitializer
        XmlEscape.escapeXml10(xml);
        XmlEscape.escapeXml11(xml);
        XmlEscape.unescapeXml(xml);

        // JavaScript — loads JavaScriptEscapeUtil
        JavaScriptEscape.escapeJavaScript(js);
        JavaScriptEscape.unescapeJavaScript(js);

        // JSON — loads JsonEscapeUtil
        JsonEscape.escapeJson(json);
        JsonEscape.unescapeJson(json);

        // CSS — loads CssEscapeUtil (identifier + string paths)
        CssEscape.escapeCssIdentifier(css);
        CssEscape.escapeCssString(css);
        CssEscape.unescapeCss(css);

        // Java — loads JavaEscapeUtil
        JavaEscape.escapeJava(java);
        JavaEscape.unescapeJava(java);

        // CSV — loads CsvEscapeUtil
        CsvEscape.escapeCsv(csv);
        CsvEscape.unescapeCsv(csv);

        // Properties — loads PropertiesEscapeUtil (key + value paths)
        PropertiesEscape.escapePropertiesKey(prop);
        PropertiesEscape.escapePropertiesValue(prop);
        PropertiesEscape.unescapeProperties(prop);

        // URI — loads UriEscapeUtil (path + query-param paths)
        UriEscape.escapeUriPath(uri);
        UriEscape.escapeUriQueryParam(uri);
        UriEscape.unescapeUriPathSegment(uri);
    }
}
