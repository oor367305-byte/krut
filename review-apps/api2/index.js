const express = require('express');
const { Pool } = require('pg');
const Redis = require('ioredis');

const app = express();
const port = process.env.PORT ? parseInt(process.env.PORT) : 5000;

console.log('Starting API2 on port', port);

const pgConfig = {
  host: process.env.PG_HOST || 'postgres',
  port: process.env.PG_PORT || 5432,
  user: process.env.PG_USER || 'postgres',
  password: process.env.PG_PASSWORD || 'postgres',
  database: process.env.PG_DB || 'review_db',
};

const redisConfig = {
  host: process.env.REDIS_HOST || 'redis',
  port: process.env.REDIS_PORT || 6379,
  retryStrategy: times => Math.min(times * 50, 2000),
};

async function getPgPool(retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      const pool = new Pool(pgConfig);
      await pool.query('SELECT 1');
      return pool;
    } catch (err) {
      console.error(`PG connect attempt ${i+1} failed:`, err.message);
      if (i === retries - 1) throw err;
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
}

async function getRedis(retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      return await new Promise((resolve, reject) => {
        const redis = new Redis(redisConfig);
        redis.on('error', err => reject(err));
        redis.on('ready', () => resolve(redis));
      });
    } catch (err) {
      console.error(`Redis connect attempt ${i+1} failed:`, err.message);
      if (i === retries - 1) throw err;
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
}

app.get('/health', async (req, res) => {
  try {
    const pgPool = await getPgPool();
    await pgPool.end();
    const redis = await getRedis();
    await redis.quit();
    console.log('Health check OK');
    res.status(200).send('OK');
  } catch (err) {
    console.error('Health check failed:', err.message);
    res.status(503).send('Service Unavailable');
  }
});

app.get('/', (req, res) => {
  res.type('text/plain').send('Hello from API2 — всё ок!\n\nTry /tasks to see sample tasks.');
});

app.get('/tasks', async (req, res) => {
  try {
    const pgPool = await getPgPool();
    const redis = await getRedis();

    const cachedTasks = await redis.get('api2:tasks');
    if (cachedTasks) {
      redis.quit();
      pgPool.end();
      return res.json(JSON.parse(cachedTasks));
    }

    const result = await pgPool.query('SELECT * FROM api2_tasks');
    const tasks = result.rows;

    await redis.set('api2:tasks', JSON.stringify(tasks), 'EX', 60);

    redis.quit();
    pgPool.end();
    res.json(tasks);
  } catch (err) {
    console.error('Tasks endpoint error:', err.message);
    res.status(500).send('Error fetching tasks');
  }
});

app.listen(port, () => console.log(`API2 successfully started on ${port}`));