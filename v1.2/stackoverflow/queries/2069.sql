WITH chrono_questions AS (
  SELECT
    u.id AS user_id,
    u.displayname,
    p.id AS post_id,
    p.title,
    p.creationdate,
    p.score,
    COALESCE(p.tags, '') AS tags
  FROM users u
  JOIN posts p ON p.owneruserid = u.id
)
SELECT
  user_id,
  displayname,
  post_id,
  title,
  creationdate,
  score,
  tags
FROM chrono_questions;