package com.api.main;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.logging.Level;
import java.util.logging.Logger;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mongodb.MongoClient;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.MongoDatabase;
import com.mongodb.client.MongoIterable;
import com.mongodb.client.model.Indexes;

import org.bson.Document;
import org.json.simple.JSONArray;
import org.json.simple.JSONObject;
import org.json.simple.parser.JSONParser;
import org.json.simple.parser.ParseException;

public class Updater {
    private static Logger LOGGER = Logger.getLogger(Updater.class.getName());
    Boolean fileParsed;
    Boolean success;

    /**
     * Backs up and updates the given mongo database with the contents of the resources/data folder.
     * @param client Mongo client that is connected to the target mongo instance
     * @param database Mongo database to backup and update
     * @return True if the update and backup completed successfully, false otherwise
     * @throws IOException If a JSON data file or it's parent directory cannot be accessed
     */
    public Boolean update(MongoClient client, MongoDatabase database) throws IOException {

        // Setup Json parser and Mongodb
        success = true;
        final JSONParser PARSER = new JSONParser();
        final MongoDatabase BACKUP_DATABASE = client.getDatabase(database.getName() + "-backup");

        // Backup and reset db
        MongoIterable<String> collections = database.listCollectionNames();
        for (String collectionName : collections) {
            LOGGER.log(Level.INFO, "[INFO] Backing up and resetting " + collectionName);

            // Delete existing valid backup if it exists
            MongoCollection<Document> backupCollection = BACKUP_DATABASE.getCollection(collectionName);
            if (backupCollection.estimatedDocumentCount() > 0) {
                backupCollection.deleteMany(new Document());
            }

            // Copy contents of collection to backup
            MongoCollection<Document> prodCollection = database.getCollection(collectionName);
            ArrayList<Document> prodContents = new ArrayList<Document>();
            prodCollection.find().into(prodContents);
            if (prodContents.size() > 0) {
                backupCollection.insertMany(prodContents);
            }

            // Delete contents of prod collection
            prodCollection.deleteMany(new Document());
            prodCollection.dropIndexes();
        }

        // In final backup stage, create the indexes
        for (String backupCollectionName : BACKUP_DATABASE.listCollectionNames()) {
            MongoCollection<Document> backupCollection = BACKUP_DATABASE.getCollection(backupCollectionName);
            backupCollection.dropIndexes();
            backupCollection.createIndex(Indexes.text());
        }

        Files.list(new File(System.getProperty("user.dir") + "/src/main/resources/data").toPath()).forEach(path -> {
            // Skip non json files
            if (!path.toString().contains(".json")) {
                LOGGER.log(Level.INFO, "[INFO] Skipping non json file in data directory : " + path);
                return;
            }

            fileParsed = true;
            LOGGER.log(Level.INFO, "[INFO] Parsing " + path);
            try {
                // Read JSON file
                final JSONArray jsonData = (JSONArray) PARSER.parse(new FileReader(path.toString()));
                jsonData.forEach(configStr -> {
                    try {
                        // Parse json string
                        final JSONObject configObj = (JSONObject) configStr;

                        // Create mongo document if there is a verified type, need a long conditional as empty types are misleading
                        if (String.valueOf(configObj.get("type")) != "" && String.valueOf(configObj.get("type")) != "\"\"" && String.valueOf(configObj.get("type")).isEmpty() == false) {
                            final Document configDoc = new Document(
                                new ObjectMapper().readValue(configObj.toJSONString(), HashMap.class)
                            );

                            // Calculate target collection based off mod and append
                            LOGGER.log(Level.INFO, "[INFO] Adding new object to database from " + path + "\n" + configObj);
                            database.getCollection("data." + configObj.get("mod").toString()).insertOne(configDoc);
                        }
                    } catch (JsonProcessingException e) {
                        LOGGER.log(Level.WARNING, "[ERROR] Could not create mongo document from config object:\n" + configStr);
                        fileParsed = false;
                    }
                });
            } catch (FileNotFoundException | ParseException e) {
                LOGGER.log(Level.SEVERE, "[ERROR] Could not find or read " + path);
                fileParsed = false;
            } catch (IOException e) {
                LOGGER.log(Level.SEVERE, "[ERROR] Could not parse " + path + " to a JSON Array");
                fileParsed = false;
            }

            if (fileParsed) {
                LOGGER.log(Level.INFO, "[SUCCESS] " + path + " successfully parsed and added to mongo db!");
            } else {
                LOGGER.log(Level.SEVERE, "[ERROR] Failed to parse file, see messages above for more info: " + path);
                success = false;
            }
        });

        // Update indices
        for (String collectionName : database.listCollectionNames()) {
            LOGGER.log(Level.INFO, "[INFO] Updating index for " + collectionName + " collection...");
            database.getCollection(collectionName).createIndex(Indexes.text());
        }

        LOGGER.log(Level.INFO, "[INFO] Updater finished, returning to main spring boot thread...");
        return success;
    }

}