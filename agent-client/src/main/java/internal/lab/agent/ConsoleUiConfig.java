package internal.lab.agent;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * P6: agent-web serves the BUILT Angular console at /console/ (mounted from
 * console/dist via compose — no node in the Java image). Same origin, so the
 * session cookie and CSRF just work; the console's offline capture mode is
 * untouched (it still ships demo-run.json inside the bundle).
 */
@Configuration
@Profile("web")
public class ConsoleUiConfig implements WebMvcConfigurer {

    private final String uiDir = System.getenv().getOrDefault("CONSOLE_UI_DIR", "/app/console-ui");

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/console/**")
                .addResourceLocations("file:" + uiDir + "/");
    }

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        registry.addViewController("/console").setViewName("forward:/console/index.html");
        registry.addViewController("/console/").setViewName("forward:/console/index.html");
    }
}
