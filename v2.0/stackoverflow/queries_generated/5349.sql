-- {"query": "5349.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 718} 
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
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
recent_activities AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.Tags,
    COALESCE(vt.Name, 'Unknown') AS VoteTypeName,
    vh.PostHistoryTypeId
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  LEFT JOIN PostHistory vh ON vh.PostId = p.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate > NOW() - INTERVAL '90 days'
),
joined_posts AS (
  SELECT
    r.*,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.Location AS OwnerLocation
  FROM recent_activities r
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
),
complex_aggregates AS (
  SELECT
    jp.PostId,
    jp.Title,
    jp.Tags,
    jp.Score,
    jp.ViewCount,
    jp.AnswerCount,
    jp.LastActivityDate,
    jp.VoteTypeName,
    -- compute a derived metric with NULL-safe arithmetic and string expressions
    (jp.Score * 1.0 / NULLIF(jp.ViewCount, 0)) AS score_per_view,
    (CASE WHEN jp.AnswerCount > 0 THEN 1 ELSE 0 END) AS has_answer,
    -- window function over recent posts to bucket activity
    SUM(CASE WHEN jp.LastActivityDate > NOW() - INTERVAL '7 days' THEN 1 ELSE 0 END) OVER () AS posts_last_7d
  FROM joined_posts jp
),
outer_joined AS (
  SELECT
    co.PostId,
    co.Title,
    co.Tags,
    co.Score,
    co.ViewCount,
    co.AnswerCount,
    co.LastActivityDate,
    co.VoteTypeName,
    co.score_per_view,
    co.has_answer,
    co.posts_last_7d,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation
  FROM complex_aggregates co
  LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = co.PostId)
),
final_selection AS (
  SELECT
    oj.PostId,
    oj.Title,
    oj.Tags,
    oj.Score,
    oj.ViewCount,
    oj.AnswerCount,
    oj.LastActivityDate,
    oj.VoteTypeName,
    oj.score_per_view,
    oj.has_answer,
    oj.posts_last_7d,
    oj.OwnerDisplayName,
    oj.OwnerReputation
  FROM outer_joined oj
  ORDER BY oj.score_per_view DESC NULLS LAST
  LIMIT 100
)
SELECT * FROM final_selection;