# Processes pubsub messages frorm car and controller and inserts them into BQ

# Components
* index.js - the Google Cloud Functions implementation in NodeJS that accepts files, processes them through the Vision and Video Intelligence API and loads the results into BigQuery
//TODO update schema file
* intelligent_content_bq_schema.json - The BigQuery schema used to create the BigQuery table.

Example cloud functions deployment
`gcloud beta functions deploy insertIntoBigQuery --stage-bucket talk-to-your-robot-temp --trigger-topic projects/talk-to-your-robot/topics/sensor-data-topic-2 --entry-point insertIntoBigQuery`
