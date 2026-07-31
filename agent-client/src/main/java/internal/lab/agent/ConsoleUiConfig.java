package internal.lab.agent;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * P6.3: ONE interface. The built Angular console (mounted from console/dist
 * via compose — no node in the Java image) is served at the ROOT; controllers
 * (/api/**, /oauth2/**, /login/**, /logout, /error) take precedence, the
 * bundle's files are the fallback for everything else.
 */
@Configuration
@Profile("web")
public class ConsoleUiConfig implements WebMvcConfigurer {

    private final String uiDir = System.getenv().getOrDefault("CONSOLE_UI_DIR", "/app/console-ui");

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/**")
                .addResourceLocations("file:" + uiDir + "/");
    }

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        registry.addViewController("/").setViewName("forward:/index.html");
        // P6.7: client-side routes of the SPA — same document, Angular routes.
        registry.addViewController("/login").setViewName("forward:/index.html");
        // Old bookmarks from the brief /console/ era.
        registry.addViewController("/console").setViewName("redirect:/");
        registry.addViewController("/console/").setViewName("redirect:/");
    }
}
