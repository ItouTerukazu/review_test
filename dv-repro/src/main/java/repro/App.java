package repro;

import org.apache.commons.text.StringEscapeUtils;

public final class App {
    private App() {}
    public static String escaped() {
        return StringEscapeUtils.escapeHtml4("<test>&");
    }
}
