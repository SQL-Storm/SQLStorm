-- {"query": "5539.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 898}
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_pop AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
),
tag_ranking AS (
  SELECT tag, COUNT(*) AS tag_count
  FROM tag_pop
  GROUP BY tag
),
top_tags AS (
  SELECT tag
  FROM tag_ranking
  ORDER BY tag_count DESC
  LIMIT 5
),
correlated AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.OwnerDisplayName,
    rq.Reputation,
    rq.Location,
    rq.LastActivityDate,
    rq.Body,
    rq.Tags,
    ARRAY_AGG(DISTINCT tt.tag) FILTER (WHERE tt.tag IS NOT NULL) AS TopTags,
    rq.OwnerUserId
  FROM recent_questions rq
  LEFT JOIN (
    SELECT DISTINCT tag FROM top_tags
  ) tt ON true
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS tag
  ) AS t
  GROUP BY rq.PostId, rq.Title, rq.CreationDate, rq.ViewCount, rq.Score, rq.OwnerDisplayName, rq.Reputation, rq.Location, rq.LastActivityDate, rq.Body, rq.Tags, rq.OwnerUserId
),
activity AS (
  SELECT
    c.PostId,
    MAX(c.Score) AS CommentScore,
    COUNT(CASE WHEN c.Score > 0 THEN 1 END) AS PositiveComments,
    COUNT(CASE WHEN c.Score < 0 THEN 1 END) AS NegativeComments,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Comments c
  GROUP BY c.PostId
),
voting AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes
  FROM Votes v
  GROUP BY v.PostId
),
joined AS (
  SELECT
    co.PostId,
    co.Title,
    co.CreationDate,
    co.ViewCount,
    co.Score,
    co.OwnerDisplayName,
    co.Reputation,
    co.Location,
    co.LastActivityDate,
    co.Body,
    co.Tags,
    co.TopTags,
    a.LastCommentDate,
    a.CommentScore,
    v.UpVotes AS PostUpVotes,
    v.DownVotes AS PostDownVotes,
    u.OwnerUserId AS OwnerUserId,
    u.UpVotes AS OwnerUpVotes,
    u.DownVotes AS OwnerDownVotes
  FROM correlated co
  LEFT JOIN activity a ON a.PostId = co.PostId
  LEFT JOIN voting v ON v.PostId = co.PostId
  LEFT JOIN (
    SELECT OwnerUserId, SUM(Score) AS UpVotes, CAST(NULL AS integer) AS DownVotes
    FROM Posts
    GROUP BY OwnerUserId
  ) u ON u.OwnerUserId = co.OwnerUserId
)
SELECT
  p.PostId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerDisplayName,
  p.Reputation,
  p.Location,
  p.LastActivityDate,
  p.Body,
  p.Tags,
  p.TopTags,
  p.LastCommentDate,
  p.CommentScore,
  p.PostUpVotes AS UpVotes,
  p.PostDownVotes AS DownVotes,
  p.OwnerUpVotes
FROM joined p
ORDER BY p.CreationDate DESC
LIMIT 100;