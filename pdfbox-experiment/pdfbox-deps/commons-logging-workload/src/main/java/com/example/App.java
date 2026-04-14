package com.example;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

public class App {
    public static void main(String[] args) {
        Log log = LogFactory.getLog(App.class);

        log.trace("trace message");
        log.debug("debug message");
        log.info("info message");
        log.warn("warn message");
        log.error("error message");
        log.fatal("fatal message");

        if (log.isTraceEnabled()) log.trace("trace enabled");
        if (log.isDebugEnabled()) log.debug("debug enabled");
        if (log.isInfoEnabled())  log.info("info enabled");
        if (log.isWarnEnabled())  log.warn("warn enabled");
        if (log.isErrorEnabled()) log.error("error enabled");
        if (log.isFatalEnabled()) log.fatal("fatal enabled");

        log.info("with throwable", new RuntimeException("boom"));

        Log namedLog = LogFactory.getLog("com.example.Named");
        namedLog.info("named log message");

        LogFactory factory = LogFactory.getFactory();
        factory.getInstance("com.example.Factory").info("factory-produced log");
    }
}
