-- {"query": "5931.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 979} 
WITH
-- sample time window for benchmarking
t AS (
  SELECT
    NOW() - INTERVAL '7 days' AS window_start,
    NOW() AS window_end
),
-- aggregate per user with complex predicates and windowing
user_metrics AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE((SELECT MAX(CreationDate) FROM Badges b WHERE b.UserId = u.Id), TIMESTAMP '1900-01-01') AS last_badge_date,
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(p.Score) AS total_post_score,
    AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId = 1) AS avg_question_score,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_received,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_received,
    COUNT(DISTINCT c.Id) AS comment_count,
    MIN(p.CreationDate) AS first_post_date,
    MAX(p.LastActivityDate) AS last_activity,
    MAX(p.LastEditDate) AS last_edit
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  CROSS JOIN t
  WHERE p.CreationDate BETWEEN t.window_start AND t.window_end
     OR c.CreationDate BETWEEN t.window_start AND t.window_end
     OR ph.CreationDate BETWEEN t.window_start AND t.window_end
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
-- compute a complex derived metric using window functions
derived AS (
  SELECT
    um.*,
    -- rank users by reputation, but break ties with last_activity
    RANK() OVER (ORDER BY um.Reputation DESC, um.last_activity DESC) AS rep_rank,
    -- moving window of top 10 posts by score per user
    SUM( CASE WHEN p2.PostTypeId IN (1,2) THEN p2.Score ELSE 0 END ) OVER (
      PARTITION BY um.Id
      ORDER BY p2.CreationDate
      ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
    ) AS last_10_score_sum
  FROM user_metrics um
  LEFT JOIN Posts p2 ON p2.OwnerUserId = um.Id
  GROUP BY um.Id, um.DisplayName, um.Reputation, um.CreationDate, um.LastAccessDate, um.Location, um.Views, um.UpVotes, um.DownVotes,
           um.post_count, um.total_post_score, um.avg_question_score, um.upvotes_received, um.downvotes_received,
           um.comment_count, um.first_post_date, um.last_activity, um.last_edit
)
SELECT
  d.Id AS user_id,
  d.DisplayName,
  d.Reputation,
  d.first_post_date,
  d.last_activity,
  d.last_edit,
  d.post_count,
  d.total_post_score,
  d.avg_question_score,
  d.upvotes_received,
  d.downvotes_received,
  d.comment_count,
  d.rep_rank,
  d.last_10_score_sum,
  -- a few advanced string and NULL expressions
  CONCAT_WS(' | ', COALESCE(d.Location, 'Unknown'), COALESCE(d.DisplayName, 'User')) AS location_display,
  CASE
    WHEN d.Reputation > 10000 THEN 'Elite'
    WHEN d.Reputation > 1000 THEN 'Pro'
    WHEN d.Reputation > 100 THEN 'Member'
    ELSE 'Newbie'
  END AS tier,
  -- correlated subquery with NULL handling and set operator
  EXISTS (
    SELECT 1
    FROM Badges b
    WHERE b.UserId = d.Id
      AND b.Class = 1
  ) AS has_gold_badge,
  -- set operation: union of top posts and top comments (simulated via exists/exists)
  (SELECT 1
     UNION ALL SELECT 1
  ) AS dummy_set
FROM derived d
ORDER BY d.rep_rank ASC, d.last_activity DESC
LIMIT 100;