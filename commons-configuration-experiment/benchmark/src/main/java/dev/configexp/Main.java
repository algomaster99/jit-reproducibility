package dev.configexp;

import org.apache.commons.configuration2.CompositeConfiguration;
import org.apache.commons.configuration2.PropertiesConfiguration;
import org.apache.commons.configuration2.XMLConfiguration;
import org.apache.commons.configuration2.builder.FileBasedConfigurationBuilder;
import org.apache.commons.configuration2.builder.fluent.Parameters;

import java.io.FileWriter;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class Main {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: Main <command> <workdir>");
            System.exit(1);
        }
        String cmd = args[0];
        Path workDir = Paths.get(args[1]);
        switch (cmd) {
            case "prepare"         -> prepare(workDir);
            case "properties-read" -> propertiesRead(workDir);
            case "xml-read"        -> xmlRead(workDir);
            case "composite-read"  -> compositeRead(workDir);
            case "interpolation"   -> interpolation(workDir);
            default -> { System.err.println("Unknown command: " + cmd); System.exit(1); }
        }
    }

    static void prepare(Path workDir) throws Exception {
        Files.createDirectories(workDir);

        try (PrintWriter pw = new PrintWriter(new FileWriter(workDir.resolve("config.properties").toFile()))) {
            pw.println("app.name=TestApp");
            pw.println("app.version=1.0");
            pw.println("database.host=localhost");
            pw.println("database.port=5432");
            pw.println("database.name=mydb");
            for (int i = 0; i < 20; i++) pw.println("key." + i + "=value" + i);
        }

        try (PrintWriter pw = new PrintWriter(new FileWriter(workDir.resolve("interpolated.properties").toFile()))) {
            pw.println("base.dir=/opt/app");
            pw.println("log.dir=${base.dir}/logs");
            pw.println("data.dir=${base.dir}/data");
            pw.println("backup.dir=${data.dir}/backup");
            pw.println("app.name=ConfigApp");
            pw.println("greeting=Hello from ${app.name}");
        }

        try (PrintWriter pw = new PrintWriter(new FileWriter(workDir.resolve("config.xml").toFile()))) {
            pw.println("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
            pw.println("<configuration>");
            pw.println("  <app><name>TestApp</name><version>2.0</version></app>");
            pw.println("  <database><host>remotehost</host><port>3306</port><name>xmldb</name></database>");
            for (int i = 0; i < 20; i++) pw.println("  <item>entry" + i + "</item>");
            pw.println("</configuration>");
        }
    }

    static void propertiesRead(Path workDir) throws Exception {
        Parameters params = new Parameters();
        FileBasedConfigurationBuilder<PropertiesConfiguration> builder =
            new FileBasedConfigurationBuilder<>(PropertiesConfiguration.class)
                .configure(params.properties()
                    .setFile(workDir.resolve("config.properties").toFile()));
        PropertiesConfiguration config = builder.getConfiguration();
        config.getProperty("app.name");
        config.getProperty("database.host");
        for (int i = 0; i < 20; i++) config.getProperty("key." + i);
    }

    static void xmlRead(Path workDir) throws Exception {
        Parameters params = new Parameters();
        FileBasedConfigurationBuilder<XMLConfiguration> builder =
            new FileBasedConfigurationBuilder<>(XMLConfiguration.class)
                .configure(params.xml()
                    .setFile(workDir.resolve("config.xml").toFile()));
        XMLConfiguration config = builder.getConfiguration();
        config.getString("app.name");
        config.getString("database.host");
        config.getString("database.port");
    }

    static void compositeRead(Path workDir) throws Exception {
        Parameters params = new Parameters();
        FileBasedConfigurationBuilder<PropertiesConfiguration> propsBuilder =
            new FileBasedConfigurationBuilder<>(PropertiesConfiguration.class)
                .configure(params.properties()
                    .setFile(workDir.resolve("config.properties").toFile()));
        FileBasedConfigurationBuilder<XMLConfiguration> xmlBuilder =
            new FileBasedConfigurationBuilder<>(XMLConfiguration.class)
                .configure(params.xml()
                    .setFile(workDir.resolve("config.xml").toFile()));

        CompositeConfiguration composite = new CompositeConfiguration();
        composite.addConfiguration(propsBuilder.getConfiguration());
        composite.addConfiguration(xmlBuilder.getConfiguration());

        composite.getString("app.name");
        composite.getString("database.host");
        composite.getString("database.name");
    }

    static void interpolation(Path workDir) throws Exception {
        Parameters params = new Parameters();
        FileBasedConfigurationBuilder<PropertiesConfiguration> builder =
            new FileBasedConfigurationBuilder<>(PropertiesConfiguration.class)
                .configure(params.properties()
                    .setFile(workDir.resolve("interpolated.properties").toFile()));
        PropertiesConfiguration config = builder.getConfiguration();
        // Accessing these keys triggers StringSubstitutor resolution via commons-text
        String logDir   = config.getString("log.dir");
        String dataDir  = config.getString("data.dir");
        String backup   = config.getString("backup.dir");
        String greeting = config.getString("greeting");
        if (logDir == null || dataDir == null || backup == null || greeting == null) {
            throw new RuntimeException("Interpolation returned null");
        }
    }
}
