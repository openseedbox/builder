import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse.BodyHandlers;
/*
 * Kudos to https://mflash.dev/blog/2021/03/01/java-based-health-check-for-docker/
 * and https://gist.github.com/jonashackt/59a405a5be94044cba754332089fb051
 */
public class HealthCheck {

    public static void main(String[] args) throws InterruptedException, IOException {
        if(args.length == 0) {
            System.out.println("Please append the App's port like: java HealthCheck.java 8098");
            throw new RuntimeException("Argument port missing");
        }

        var request = HttpRequest.newBuilder()
                .uri(URI.create("http://localhost:" + args[0] + "/health"))
                .header("accept", "application/json")
                .build();

        var response = HttpClient.newHttpClient().send(request, BodyHandlers.ofString());

        if (response.statusCode() != 200 || !response.body().contains("UP")) {
            throw new RuntimeException("Healthcheck failed");
        }
    }
}
