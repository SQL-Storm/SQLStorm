-- {"query": "5743.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 733} 
WITH
recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
),
top_authors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rank
  FROM Users u
  WHERE u.Reputation > 1000
),
tag_scores AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS total_score,
    COUNT(*) AS post_count,
    AVG(p.Score) AS avg_score
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id,
      p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) AS t1
  GROUP BY t.TagName
),
complex_filter AS (
  SELECT
    rp.Id,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount
  FROM recent_posts rp
  LEFT JOIN top_authors ta ON rp.OwnerUserId = ta.UserId
  LEFT JOIN LATERAL (
    SELECT
      SUM(v.BountyAmount) AS total_bounty,
      COUNT(*) AS vote_count
    FROM Votes v
    WHERE v.PostId = rp.Id
      AND v.VoteTypeId IN (2, 3, 6)
  ) vstats ON TRUE
  LEFT JOIN PostLinks pl ON pl.PostId = rp.Id
  LEFT JOIN Votes vv ON vv.PostId = rp.Id
  LEFT JOIN TagScores ts ON ts.TagName = ANY(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><'))
  WHERE rp.Score > 0
    OR rp.ViewCount > 1000
    OR ta.rank <= 100
    OR vstats.total_bounty IS NOT NULL
)
SELECT
  cf.Id AS post_id,
  cf.PostTypeId,
  cf.OwnerUserId,
  cu.DisplayName AS owner_display,
  cf.Title,
  cf.Tags,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.Score,
  cf.ViewCount,
  cf.CommentCount,
  cf.AnswerCount,
  cf.FavoriteCount,
  vtypes.Name AS vote_type_for_bypass
FROM complex_filter cf
LEFT JOIN Users cu ON cf.OwnerUserId = cu.Id
LEFT JOIN Votes v ON v.PostId = cf.Id
LEFT JOIN VoteTypes vtypes ON v.VoteTypeId = vtypes.Id
WHERE
  (cf.Score > 0 AND cf.Views IS NULL)
  OR (cf.ViewCount > 5000)
  OR (cf.LastActivityDate > cf.CreationDate)
ORDER BY cf.LastActivityDate DESC, cf.Score DESC
LIMIT 200;