package com.api.main;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.logging.FileHandler;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.logging.SimpleFormatter;
import java.util.stream.Collectors;

import com.mongodb.MongoClient;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.MongoDatabase;
import com.mongodb.client.model.Filters;

import org.bson.Document;
import org.json.simple.parser.ParseException;
import org.springframework.boot.ExitCodeGenerator;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.mongo.MongoAutoConfiguration;
import org.springframework.context.ApplicationContext;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@EnableAutoConfiguration(exclude = {MongoAutoConfiguration.class})
@RestController
public class Executer {
    private static MongoDatabase DATABASE;
    private static Logger LOGGER = Logger.getLogger(Executer.class.getName());
    private static FileHandler HANDLER;
    private static Config config;

    public static void main(String[] args) throws FileNotFoundException, IOException, ParseException, Exception {
        ApplicationContext context = SpringApplication.run(Executer.class, args);
        config = context.getBean(Config.class);

        // Setup logging
        try {
            LOGGER.setLevel(Level.INFO);
            HANDLER = new FileHandler(config.getLogfilePath());
            LOGGER.addHandler(HANDLER);
            SimpleFormatter formatter = new SimpleFormatter();
            HANDLER.setFormatter(formatter);
        } catch (IOException e) {
            System.err.println("[ERROR] Failed to initialise File Handler for logging");
            e.printStackTrace();
        }

        // Connect to target mongo instance and database
        final MongoClient MONGO_CLIENT = new MongoClient(config.getMongoUri());
        DATABASE = MONGO_CLIENT.getDatabase(config.getMongoDatabaseName());

        // Run the updater if requested
        if (Arrays.asList(args).contains("--updater")) {
            try {
                if (new Updater().update(MONGO_CLIENT, DATABASE) == true) {
                    LOGGER.log(Level.INFO, "[SUCCESS] Updater has successfully backed up and updated all collections in the database!");
                } else {
                    throw new Exception("[ERROR] Updater failed to backup and/or update all collections in the database. See log for more details...");
                }
            } catch (Exception e) {
                LOGGER.log(Level.SEVERE, "[ERROR] Updater threw an exception, see log for details");
                throw e;
            } finally {
                // Close after update completes
                MONGO_CLIENT.close();
                SpringApplication.exit(context, new ExitCodeGenerator() {
                    @Override
                    public int getExitCode() {
                        // Return the error code
                        return 0;
                    }
                });
            }
        }
    }

    /**
     * The base API route for the class list, this will return all the classes in the database by default. Optionally, {@code mod} can be added to the path to filter the classes by a specific mod. In addition or in lieu, {@code type} can be added as a request parameter ({@code ?type=<the-type>}) to filter the classes by the type of each config (e.g. weapon, backpack, etc).
     * @param mod A mod to filter for (e.g. ace, vanilla, 3cb)
     * @param type A type to filter for (e.g. weapon, vest, headgear)
     * @param page Pagination page number
     * @param size Pagination page size (max number of items in the json array on each page)
     * @return A string representation of JSON list containing the filtered configs
     * @throws Exception The user has provided a mod or type that isn't valid
     */
    @GetMapping(value = {"/classes", "/classes/{mod}"})
    public String classes (
        @PathVariable(required = false, value = "mod") String mod,
        @RequestParam(required = false, value = "type") String type,
        @RequestParam(required = false, value = "page", defaultValue = "0") Integer page,
        @RequestParam(required = false, value = "size", defaultValue = "-1") Integer size
    ) throws Exception {
        LOGGER.log(Level.INFO, String.format("Executing /classes endpoint with parameters %s (mod) and %s (type) and %s (page) and %s (size)", mod, type, page, size));

        // Check user input
        final String filteredMod = mod == "" || mod == null ? "" : escapeUserInput(mod);
        final String filteredType = type == "" || type == null ? "" : escapeUserInput(type);

        // Verify params
        if (!config.getMods().contains(filteredMod) && filteredMod != "") {
            throw new Exception(String.format("Unidentified mod (%s). Available values are %s", filteredMod, config.getMods().toString()));
        }
        if (!Config.getTypes().contains(filteredType) && filteredType != "") {
            throw new Exception(String.format("Unidentified object type (%s). Available values are %s", filteredType, Config.getTypes().toString()));
        }

        // Filter db by keywords or return all
        ArrayList<Document> dbContents = new ArrayList<Document>();
        for (String collectionName : DATABASE.listCollectionNames()) {
            MongoCollection<Document> modContents = retrieveCollection(collectionName);

            if (collectionName.equals("data." + filteredMod)) {
                dbContents.addAll(filterByType(modContents, filteredType));

                // Break so we only return a singular mod spec
                break;
            } else if (filteredMod.isEmpty()) {
                dbContents.addAll(filterByType(modContents, filteredType));
            } else {
                // We haven't reached the requested mod yet
                continue;
            }
        }

        // Prettify and respond
        if (size == -1) {
            return String.valueOf(dbContents
                .stream()
                .distinct()
                .map(typeDoc -> typeDoc.toJson())
                .sorted()
                .collect(Collectors.toList())
            );
        } else {
            Integer pageLimter = size * page;
            if (page == 0) {
                pageLimter = 0;
            }
            return String.valueOf(dbContents
                .stream()
                .skip(pageLimter)
                .limit(size)
                .distinct()
                .map(typeDoc -> typeDoc.toJson())
                .sorted()
                .collect(Collectors.toList())
            );
        }
    }

    /**
     * A search route for the class list, this will return all the classes in the database that match a user provided search term (after escaping mongo chars).
     * @param term The search term. It can be a classname, a config key or a config value
     * @param page Pagination page number
     * @param size Pagination page size (max number of items in the json array on each page)
     * @return A string representation of JSON list containing the filtered configs
     * @throws Exception If a collection cannot be found or is malformed
     */
    @GetMapping(value = {"/classes/search/{term}"})
    public String search (
        @PathVariable(required = true, value = "term") String term,
        @RequestParam(required = false, value = "page", defaultValue = "0") Integer page,
        @RequestParam(required = false, value = "size", defaultValue = "-1") Integer size
    ) throws Exception {
        LOGGER.log(Level.INFO, String.format("Executing /classes/search endpoint with parameters %s (term) and %s (page) and %s (size)", term, page, size));

        // Escape user input
        final String filteredTerm = escapeUserInput(term);

        // Match using Bson filter
        ArrayList<Document> matchedClasses = new ArrayList<Document>();
        for (String modName : DATABASE.listCollectionNames()) {
            ArrayList<Document> filteredContents = new ArrayList<Document>();
            try {
                // TODO: This will need updating as we add more numeric fields
                retrieveCollection(modName).find(Filters.or(
                    Filters.eq("count", Long.parseLong(filteredTerm)),
                    Filters.eq("weight", Long.parseLong(filteredTerm))
                )).into(filteredContents);
            } catch (NumberFormatException e) {
                retrieveCollection(modName).find(Filters.text(filteredTerm)).into(filteredContents);
            }

            // Add to final doc if match is found
            if (filteredContents != null) {
                matchedClasses.addAll(filteredContents);
            }
        }

        // Prettify and respond
        if (size == -1) {
            return String.valueOf(matchedClasses
                .stream()
                .distinct()
                .map(typeDoc -> typeDoc.toJson())
                .sorted()
                .collect(Collectors.toList())
            );
        } else {
            Integer pageLimter = size * page;
            if (page == 0) {
                pageLimter = 0;
            }
            return String.valueOf(matchedClasses
                .stream()
                .skip(pageLimter)
                .limit(size)
                .distinct()
                .map(typeDoc -> typeDoc.toJson())
                .sorted()
                .collect(Collectors.toList())
            );
        }
    }

    /**
     * Retrieves a MongoDB collection based off the collection string
     * @param collectionName The name of a collection to retrieve
     * @return A MongoDB collection
     * @throws Exception If the collection doesn't exist or is malformed
     */
    private MongoCollection<Document> retrieveCollection(String collectionName) throws Exception {
        ArrayList<String> collections = new ArrayList<String>();
        DATABASE.listCollectionNames().into(collections);
        if (collections.contains(collectionName)) {
            return DATABASE.getCollection(collectionName);
        } else {
            throw new Exception(collectionName + " does not exist or is an unknown class type");
        }
    }

    /**
     * Escapes a user input from the url path or request parameters to remove all special mongo charecters
     * @param unfilteredInput The unfiltered user input straight from the url
     * @return A filtered input without any special charecters added
     */
    private String escapeUserInput(String unfilteredInput) {
        LOGGER.log(Level.INFO, "Escaping user input string: " + unfilteredInput);
        String filteredInput = "";
        for (int i = 0; i < unfilteredInput.length(); i++) {
            char currentCharecter = unfilteredInput.charAt(i);
            if (!Config.getSpecialChars().contains(currentCharecter)) {
                filteredInput += currentCharecter;
            }
        }
        return filteredInput;
    }

    /**
     * Filters a given collection by a user requested type or retrieves all the types if user input is not given.
     * @param collection The collection to search in
     * @param type The config type to filter the collection by
     * @return A list of all the documents in the collection that matches the type (or all if no type was given)
     */
    private ArrayList<Document> filterByType(MongoCollection<Document> collection, String type) {
        ArrayList<Document> filteredContents = new ArrayList<Document>();
        if (type.isEmpty()) {
            // Get all types
            collection.find().into(filteredContents);
        } else {
            // Filter by type
            collection.find(Filters.eq("type", type)).into(filteredContents);
        }
        return filteredContents;
    }

}
