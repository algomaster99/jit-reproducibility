package dev.batikexp;

import org.apache.batik.anim.dom.SAXSVGDocumentFactory;
import org.apache.batik.svggen.SVGGeneratorContext;
import org.apache.batik.svggen.SVGGraphics2D;
import org.apache.batik.transcoder.TranscoderInput;
import org.apache.batik.transcoder.TranscoderOutput;
import org.apache.batik.transcoder.image.JPEGTranscoder;
import org.apache.batik.transcoder.image.PNGTranscoder;
import org.apache.batik.transcoder.svg2svg.SVGTranscoder;
import org.apache.batik.util.XMLResourceDescriptor;
import org.w3c.dom.Document;
import org.w3c.dom.svg.SVGDocument;

import javax.xml.parsers.DocumentBuilderFactory;
import java.awt.*;
import java.awt.geom.Ellipse2D;
import java.awt.geom.Line2D;
import java.io.*;
import java.nio.file.*;

public class Main {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: Main <command> <workdir>");
            System.exit(1);
        }
        String cmd = args[0];
        Path workDir = Paths.get(args[1]);
        switch (cmd) {
            case "prepare"      -> prepare(workDir);
            case "svg-parse"    -> svgParse(workDir);
            case "svg-to-png"   -> svgToPng(workDir);
            case "svg-to-jpeg"  -> svgToJpeg(workDir);
            case "svg-to-svg"   -> svgToSvg(workDir);
            case "svg-generate" -> svgGenerate(workDir);
            default -> { System.err.println("Unknown command: " + cmd); System.exit(1); }
        }
    }

    // -------------------------------------------------------------------------
    // prepare
    // -------------------------------------------------------------------------

    static void prepare(Path workDir) throws Exception {
        Files.createDirectories(workDir);
        Files.writeString(workDir.resolve("simple.svg"), SIMPLE_SVG);
    }

    // -------------------------------------------------------------------------
    // svg-parse: load SVG into a DOM tree without rendering
    // -------------------------------------------------------------------------

    static void svgParse(Path workDir) throws Exception {
        String parser = XMLResourceDescriptor.getXMLParserClassName();
        SAXSVGDocumentFactory factory = new SAXSVGDocumentFactory(parser);
        File svg = workDir.resolve("simple.svg").toFile();
        SVGDocument doc = factory.createSVGDocument(svg.toURI().toString());
        // Touch the root element to ensure the DOM is fully realised
        doc.getDocumentElement().getTagName();
    }

    // -------------------------------------------------------------------------
    // svg-to-png: rasterise SVG → PNG (single.aot training op)
    // -------------------------------------------------------------------------

    static void svgToPng(Path workDir) throws Exception {
        PNGTranscoder t = new PNGTranscoder();
        File svg = workDir.resolve("simple.svg").toFile();
        try (InputStream in = new FileInputStream(svg);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            t.transcode(new TranscoderInput(in), new TranscoderOutput(out));
        }
    }

    // -------------------------------------------------------------------------
    // svg-to-jpeg: rasterise SVG → JPEG
    // -------------------------------------------------------------------------

    static void svgToJpeg(Path workDir) throws Exception {
        JPEGTranscoder t = new JPEGTranscoder();
        t.addTranscodingHint(JPEGTranscoder.KEY_QUALITY, 0.8f);
        File svg = workDir.resolve("simple.svg").toFile();
        try (InputStream in = new FileInputStream(svg);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            t.transcode(new TranscoderInput(in), new TranscoderOutput(out));
        }
    }

    // -------------------------------------------------------------------------
    // svg-to-svg: normalise/pretty-print SVG via SVGTranscoder
    // -------------------------------------------------------------------------

    static void svgToSvg(Path workDir) throws Exception {
        SVGTranscoder t = new SVGTranscoder();
        File svg = workDir.resolve("simple.svg").toFile();
        try (Reader in = new FileReader(svg);
             StringWriter out = new StringWriter()) {
            t.transcode(new TranscoderInput(in), new TranscoderOutput(out));
        }
    }

    // -------------------------------------------------------------------------
    // svg-generate: produce SVG from Java2D calls via SVGGraphics2D
    // -------------------------------------------------------------------------

    static void svgGenerate(Path workDir) throws Exception {
        Document doc = DocumentBuilderFactory.newInstance()
                .newDocumentBuilder().newDocument();

        SVGGeneratorContext ctx = SVGGeneratorContext.createDefault(doc);
        SVGGraphics2D g2 = new SVGGraphics2D(ctx, false);
        g2.setSVGCanvasSize(new Dimension(300, 300));

        // Draw a mix of primitives to exercise the SVGGraphics2D paint paths
        g2.setColor(Color.BLUE);
        g2.fillRect(20, 20, 80, 80);

        g2.setColor(Color.RED);
        g2.fill(new Ellipse2D.Float(120, 20, 80, 80));

        g2.setStroke(new BasicStroke(3f));
        g2.setColor(Color.GREEN);
        g2.draw(new Line2D.Float(20, 200, 280, 200));

        g2.setFont(new Font("SansSerif", Font.BOLD, 18));
        g2.setColor(Color.BLACK);
        g2.drawString("batik svg-generate", 30, 260);

        StringWriter sw = new StringWriter();
        g2.stream(sw, true);
    }

    // -------------------------------------------------------------------------
    // Embedded SVG sources
    // -------------------------------------------------------------------------

    private static final String SIMPLE_SVG =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
        "<svg xmlns=\"http://www.w3.org/2000/svg\"\n" +
        "     xmlns:xlink=\"http://www.w3.org/1999/xlink\"\n" +
        "     width=\"400\" height=\"400\" viewBox=\"0 0 400 400\">\n" +
        "  <defs>\n" +
        "    <linearGradient id=\"grad\" x1=\"0%\" y1=\"0%\" x2=\"100%\" y2=\"100%\">\n" +
        "      <stop offset=\"0%\"   stop-color=\"#4a90d9\"/>\n" +
        "      <stop offset=\"100%\" stop-color=\"#d94a4a\"/>\n" +
        "    </linearGradient>\n" +
        "  </defs>\n" +
        "  <rect width=\"400\" height=\"400\" fill=\"#f5f5f5\"/>\n" +
        "  <rect x=\"40\" y=\"40\" width=\"140\" height=\"140\" rx=\"12\" fill=\"url(#grad)\"/>\n" +
        "  <circle cx=\"280\" cy=\"110\" r=\"70\" fill=\"#4ad94a\" opacity=\"0.85\"/>\n" +
        "  <polygon points=\"60,360 200,220 340,360\" fill=\"#d9d44a\"/>\n" +
        "  <text x=\"200\" y=\"390\" font-family=\"Arial\" font-size=\"14\"\n" +
        "        text-anchor=\"middle\" fill=\"#333\">batik benchmark</text>\n" +
        "</svg>\n";

}
