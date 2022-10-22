package main

/*
A small, dedicated SSE listener that listens on the wikipedia recent changes event streams
endpoint (see below) and pushes the incoming events into a MySQL table (or any DB compatible w. t
he MySQL wire protocol)

more on wikipedia recent events:
	- https://github.com/wikimedia/mediawiki-services-eventstreams
	- https://wikitech.wikimedia.org/wiki/Event_Platform/EventStreams
	- https://stream.wikimedia.org/v2/ui/#/

to run locally (using MYSQL don't worry, event stream is <100 rps, it'll be OK): docker-compose up,
in practice, I just deploy the binary to an instance.
*/

import (
	"fmt"
	"os"
	"time"

	"context"
	"database/sql"
	"encoding/json"
	"sync"

	retry "github.com/avast/retry-go"
	aws "github.com/aws/aws-sdk-go/aws"
	session "github.com/aws/aws-sdk-go/aws/session"
	ssm "github.com/aws/aws-sdk-go/service/ssm"
	_ "github.com/go-sql-driver/mysql"
	sse "github.com/r3labs/sse/v2"
	log "github.com/sirupsen/logrus"
)

const localEnv = "local"

var (
	// dbcredentials - default to `dbHost` or `dbPassword` where SSM parameters not defined...
	dbHostNameParam = os.Getenv("MYSQL_HOSTNAME_PARAM") // default: /wiki-singlestore/database/host
	dbHost          = os.Getenv("MYSQL_HOSTNAME")       // default: mysql
	dbPasswordParam = os.Getenv("MYSQL_PASSWORD_PARAM") // default: /wiki-singlestore/database/password
	dbPassword      = os.Getenv("MYSQL_PASSWORD")       // default: writer-password
	dbPort          = 3306
	dbUser          = "writer"
	dbName          = "wikipedia"

	// message consumtion configuration
	recentChangesEndpoint = "https://stream.wikimedia.org/v2/stream/recentchange"
	numDBWriters          = 8
)

var (
	eventIngestStmt = `INSERT INTO rchanges (id, timestamp, wiki, type, byte_delta) VALUES (?, ?, ?, ?, ?)`
)

// Event - represents an incoming event of default SSE event (schema: `/mediawiki/recentchange/1.0.0`)
// includes an anonymous internal ByteRevision struct
type Event struct {
	Timestamp    int64  `json:"timestamp"`
	Wiki         string `json:"wiki"`
	Type         string `json:"type"`
	ByteRevision struct {
		Old int64 `json:"old"`
		New int64 `json:"new"`
	} `json:"length"`
	Meta struct {
		ID string `json:"id"`
	} `json:"meta"`
}

// DBWriter - wrapper around a sql.DB connection, handles DB credentials, connection initialization
// retries on connection failure, etc.
//
// note: assumes `dbHostNameParam`, `dbPasswordParam` are secret, and all other credentials are
// public
type DBWriter struct {
	db                               *sql.DB
	dbHostNameParam, dbPasswordParam *string // SSM parameter names
	dbUser                           string
	dbName                           string
	dbPort                           int
}

// initDBConnection - init
func (w *DBWriter) initDBConnection(ctx context.Context, client *ssm.SSM) error {

	mysqlHost := &dbHost
	mysqlPassword := &dbPassword

	environment := os.Getenv("ENV")
	if (localEnv != environment) && (environment != "") {

		log.WithFields(log.Fields{
			"env": environment,
		}).Info("using remote environment")

		//
		var withDecryption = true
		getParametersOut, err := client.GetParameters(
			&ssm.GetParametersInput{
				Names:          []*string{w.dbHostNameParam, w.dbPasswordParam},
				WithDecryption: &withDecryption,
			},
		)

		//
		if (err != nil) || (len(getParametersOut.InvalidParameters) > 0) {
			log.WithFields(log.Fields{
				"error":                     err,
				"failed_parameter_requests": getParametersOut.InvalidParameters,
			}).Error("failed to locate requested parameters")
			return err
		}

		//
		mysqlHost = getParametersOut.Parameters[0].Value
		mysqlPassword = getParametersOut.Parameters[1].Value
	}

	// open connection & ping DB in a backoff retry loop
	err := retry.Do(
		func() error {
			db, err := sql.Open("mysql", fmt.Sprintf("%s:%s@tcp(%s:%d)/%s", w.dbUser, *mysqlPassword, *mysqlHost, w.dbPort, w.dbName))
			if err != nil {
				log.WithFields(log.Fields{
					"error":    err,
					"user":     w.dbUser,
					"hostname": mysqlHost,
					"port":     w.dbPort,
					"db":       w.dbName,
				}).Error("failed to connect to db, invalid connection details")
				return err
			}

			if err := db.PingContext(ctx); err != nil {
				log.WithFields(log.Fields{
					"error": err,
				}).Error("failed to connect to db, failed to ping db")

				// check for context cancelation
				if ctx.Err() != nil {
					log.WithFields(log.Fields{"error": ctx.Err()}).Error("context canceled")
					return retry.Unrecoverable(ctx.Err())
				}

				return err
			}

			//
			db.SetConnMaxIdleTime(time.Millisecond * 1000 * 32 * 16)
			db.SetConnMaxLifetime(time.Millisecond * 1000 * 32 * 16)
			db.SetMaxIdleConns(numDBWriters)
			db.SetMaxOpenConns(numDBWriters)

			w.db = db
			return nil
		},
		retry.Attempts(5),          // caps at ~60s total wait
		retry.Delay(time.Second*2), // 2 + 4 + 8 + 16 + 32 -> err
	)

	return err
}

// WriteEventsToDB - writes events to an `rchanges` changes table w. a specific structure
func (w *DBWriter) WriteEventsToDB(ctx context.Context, wg *sync.WaitGroup, C chan *sse.Event) error {
	defer wg.Done()
	var evt Event
	for {
		select {
		case msg := <-C:
			// event msg -> event struct
			if err := json.Unmarshal(msg.Data, &evt); err != nil {
				log.WithFields(log.Fields{
					"error": err,
				}).Error("error decoding recent change event")
			}

			// event struct -> db
			if _, err := w.db.ExecContext(ctx, eventIngestStmt, evt.Meta.ID, evt.Timestamp, evt.Wiki, evt.Type, evt.ByteRevision.New-evt.ByteRevision.Old); err != nil {
				log.WithFields(log.Fields{
					"error": err,
					"event": fmt.Sprintf("%+v", evt),
				}).Error("error writing event to db")
			}
		case <-ctx.Done():
			log.WithFields(log.Fields{"error": ctx.Err()}).Error("ctx expired")
			return nil
		}
	}
}

func initOrRefreshTopicSubscription(client *sse.Client, C chan *sse.Event) error {
	if err := client.SubscribeChan("messages", C); err != nil {
		return err
	}
	return nil
}

func init() {
	log.SetFormatter(&log.TextFormatter{FullTimestamp: true})
	log.SetLevel(log.InfoLevel)
}

func main() {

	// init AWS SSM client
	awsSession := session.Must(session.NewSession())
	ssmClient := ssm.New(awsSession, aws.NewConfig().WithRegion("us-east-1"))

	dbwr := DBWriter{
		dbHostNameParam: &dbHostNameParam,
		dbPasswordParam: &dbPasswordParam,
		dbUser:          dbUser,
		dbName:          dbName,
		dbPort:          dbPort,
	}

	// crashloop on fail to connect to db...
	if err := dbwr.initDBConnection(context.Background(), ssmClient); err != nil {
		log.WithFields(log.Fields{
			"bHostNameParam":  dbHostNameParam,
			"dbPasswordParam": dbPasswordParam,
			"dbUser":          dbUser,
			"dbName":          dbName,
			"dbPort":          dbPort,
		}).Fatal("error initializing db connections")
	}
	defer dbwr.db.Close()

	// https://phabricator.wikimedia.org/T242767 - init SSE configuration
	for {

		var wg sync.WaitGroup
		ctx, cancel := context.WithTimeout(context.Background(), 20*60*time.Second)
		defer cancel()

		events := make(chan *sse.Event)
		sseClient := sse.NewClient(recentChangesEndpoint)

		defer func() {
			sseClient.Unsubscribe(events)
			close(events)
		}()

		if err := initOrRefreshTopicSubscription(sseClient, events); err != nil {
			log.WithFields(log.Fields{
				"err": err,
			}).Fatal("error on channel subscribe")
		}
		log.Info("reinitializing worker contexts")

		// consume events off SSE stream forever...
		for i := 0; i < numDBWriters; i++ {
			wg.Add(1)
			go dbwr.WriteEventsToDB(ctx, &wg, events)
		}
		wg.Wait()
	}

}
