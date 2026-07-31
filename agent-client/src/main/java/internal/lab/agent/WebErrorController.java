package internal.lab.agent;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.webmvc.error.ErrorController;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;

import jakarta.servlet.RequestDispatcher;
import jakarta.servlet.http.HttpServletRequest;

/**
 * P2.5: no whitelabel pages on stage. Anything that falls through to /error
 * (stale session after a restart, bad URL) is logged server-side and the
 * browser is sent back to the front page, where a fresh login is one click.
 */
@Controller
@Profile("web")
public class WebErrorController implements ErrorController {

    private static final Logger log = LoggerFactory.getLogger(WebErrorController.class);

    @RequestMapping("/error")
    public String recover(HttpServletRequest request) {
        Object status = request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE);
        Object uri = request.getAttribute(RequestDispatcher.ERROR_REQUEST_URI);
        log.warn("recovering browser from error status={} uri={}", status, uri);
        return "redirect:/";
    }
}
