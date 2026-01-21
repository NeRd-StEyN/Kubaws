const express = require('express');
const cors = require('cors');
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// AWS Clients
// In Lambda/EC2, region is usually picked up from the environment or IAM role
const region = process.env.AWS_REGION || "us-east-1";
const dbClient = new DynamoDBClient({ region });
const docClient = DynamoDBDocumentClient.from(dbClient);
const snsClient = new SNSClient({ region });

// Prometheus setup
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestCounter = new client.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status_code'],
});

// Middleware to count requests
app.use((req, res, next) => {
    res.on('finish', () => {
        httpRequestCounter.labels(req.method, req.route ? req.route.path : req.path, res.statusCode).inc();
    });
    next();
});

const TABLE_NAME = "DevOpsMessages";
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN;

// Health check
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'UP', timestamp: new Date().toISOString() });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
});

// GET: Fetch all messages from DynamoDB
app.get('/api/message', async (req, res) => {
    try {
        const command = new ScanCommand({ TableName: TABLE_NAME });
        const response = await docClient.send(command);
        res.json({
            message: 'Current messages in cloud database',
            data: response.Items || []
        });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Could not fetch from DynamoDB', details: err.message });
    }
});

// POST: Save a new message and trigger SNS
app.post('/api/message', async (req, res) => {
    const { text } = req.body;
    if (!text) return res.status(400).json({ error: 'Text is required' });

    const newItem = {
        id: Date.now().toString(),
        text,
        timestamp: new Date().toISOString()
    };

    try {
        // 1. Save to DynamoDB
        await docClient.send(new PutCommand({
            TableName: TABLE_NAME,
            Item: newItem
        }));

        // 2. Notify via SNS (if configured)
        if (SNS_TOPIC_ARN) {
            await snsClient.send(new PublishCommand({
                TopicArn: SNS_TOPIC_ARN,
                Message: `New message received in DevOps App: "${text}"`,
                Subject: "DevOps App Notification"
            }));
        }

        res.status(201).json({ status: 'Saved to DynamoDB + SNS Sent', item: newItem });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Cloud action failed', details: err.message });
    }
});

app.listen(PORT, () => {
    console.log(`Cloud-Ready Backend running on http://localhost:${PORT}`);
});
