-- init.sql
CREATE TABLE IF NOT EXISTS api1_items (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  value INTEGER NOT NULL
);

INSERT INTO api1_items (name, value)
  SELECT 'Item A', 10
  WHERE NOT EXISTS (SELECT 1 FROM api1_items WHERE name='Item A');

INSERT INTO api1_items (name, value)
  SELECT 'Item B', 20
  WHERE NOT EXISTS (SELECT 1 FROM api1_items WHERE name='Item B');

CREATE TABLE IF NOT EXISTS api2_tasks (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT
);

INSERT INTO api2_tasks (title, description)
  SELECT 'Task 1', 'Description for task 1'
  WHERE NOT EXISTS (SELECT 1 FROM api2_tasks WHERE title='Task 1');

INSERT INTO api2_tasks (title, description)
  SELECT 'Task 2', 'Description for task 2'
  WHERE NOT EXISTS (SELECT 1 FROM api2_tasks WHERE title='Task 2');