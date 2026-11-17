-- Every intention now points at a task. Give each upcoming intention that was
-- made from a suggestion its own task (title from the suggestion, estimate from
-- the block's length), added after the goal's other tasks, and link them.
WITH src AS MATERIALIZED (
  SELECT
    b.id AS block_id,
    gen_random_uuid() AS task_id,
    b.user_id,
    b.goal_id,
    b.from_suggestion AS title,
    CASE
      WHEN b.ends_at - b.starts_at <= interval '15 minutes' THEN 15
      WHEN b.ends_at - b.starts_at <= interval '30 minutes' THEN 30
      WHEN b.ends_at - b.starts_at <= interval '60 minutes' THEN 60
      ELSE 120
    END AS minutes,
    1000 + row_number() OVER (PARTITION BY b.goal_id ORDER BY b.starts_at) AS position
  FROM calendar_blocks b
  WHERE b.from_suggestion IS NOT NULL AND b.task_id IS NULL AND b.ends_at > now()
),
created AS (
  INSERT INTO goal_tasks (id, user_id, goal_id, title, minutes, position)
  SELECT task_id, user_id, goal_id, title, minutes, position FROM src
  RETURNING id
)
UPDATE calendar_blocks b
SET task_id = src.task_id
FROM src
WHERE b.id = src.block_id AND src.task_id IN (SELECT id FROM created);
