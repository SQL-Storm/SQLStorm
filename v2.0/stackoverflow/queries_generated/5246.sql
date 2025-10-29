-- {"query": "5246.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 746} 
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body
  FROM Posts p
  WHERE p.CreationDate >= DATEADD(day, -180, CURRENT_DATE)
),
activity_summary AS (
  SELECT
    rp.OwnerUserId,
    COUNT(*) AS posts_last_180d,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_last_180d,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers_last_180d,
    SUM(p.Score) AS score_last_180d,
    MAX(p.LastActivityDate) AS last_activity
  FROM recent_posts rp
  LEFT JOIN Posts p ON rp.PostId = p.Id
  GROUP BY rp.OwnerUserId
),
qualified_users AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    ascore.posts_last_180d,
    ascore.questions_last_180d,
    ascore.answers_last_180d,
    ascore.score_last_180d,
    ascore.last_activity
  FROM top_users tu
  LEFT JOIN activity_summary ascore ON tu.UserId = ascore.OwnerUserId
  WHERE tu.rn <= 100
),
complex_calc AS (
  SELECT
    qu.UserId,
    qu.DisplayName,
    qu.Reputation,
    qu.posts_last_180d,
    qu.questions_last_180d,
    qu.answers_last_180d,
    qu.score_last_180d,
    qu.last_activity,
    -- advanced metrics with NULL-safe expressions
    (COALESCE(qu.score_last_180d,0) * 1.0) / NULLIF(COALESCE(qu.posts_last_180d,0),0) AS avg_score_per_post,
    (COALESCE(qu.views,0) + COALESCE(qu.UpVotes,0) - COALESCE(qu.DownVotes,0)) AS net_reputation_metric,
    -- window-like calculation: time since last activity
    DATEDIFF(day, qu.last_activity, CURRENT_DATE) AS days_since_last_activity,
    -- tag-related string manipulation: derive tag richness
    (SELECT COUNT(*) FROM unnest(string_to_array(qu.Title, ' ')) AS tword) AS title_word_count
  FROM qualified_users qu
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.posts_last_180d,
  c.questions_last_180d,
  c.answers_last_180d,
  c.score_last_180d,
  c.last_activity,
  c.avg_score_per_post,
  c.net_reputation_metric,
  c.days_since_last_activity,
  c.title_word_count
FROM complex_calc c
ORDER BY c.Reputation DESC NULLS LAST, c.last_activity DESC
LIMIT 200;