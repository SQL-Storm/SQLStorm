-- {"query": "6050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 745} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
top_repliers AS (
  SELECT
    q.PostId,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(*) OVER (PARTITION BY q.PostId) AS repl_count
  FROM recent_questions q
  LEFT JOIN Posts a ON a.ParentId = q.PostId
  LEFT JOIN Users u ON (CASE
      WHEN a.OwnerUserId IS NOT NULL THEN a.OwnerUserId
      WHEN q.OwnerUserId IS NOT NULL THEN q.OwnerUserId
      ELSE NULL
    END) = u.Id
  WHERE a.Id IS NOT NULL
),
tag_stats AS (
  SELECT
    q.PostId,
    t.TagName,
    COUNT(*) AS tag_count
  FROM recent_questions q
  JOIN LATERAL string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><') AS tarr ON true
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS t(TagName)
  GROUP BY q.PostId, t.TagName
),
complex_pred AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.LastActivityDate,
    q.CommentCount,
    COALESCE(vt.LastVote, 0) AS LastVote
  FROM recent_questions q
  LEFT JOIN (
    SELECT PostId, MAX(CreationDate) AS LastVote
    FROM Votes
    WHERE VoteTypeId = 2 -- UpMod
    GROUP BY PostId
  ) vt ON vt.PostId = q.PostId
),
exists_recent_comments AS (
  SELECT c.PostId, COUNT(*) AS CommentCountRecent
  FROM Comments c
  WHERE c.CreationDate > NOW() - INTERVAL '7 days'
  GROUP BY c.PostId
)
SELECT
  cr.PostId,
  cr.Title,
  cr.Tags,
  cr.CreationDate,
  cr.Score,
  cr.ViewCount,
  cr.OwnerUserId,
  cr.LastActivityDate,
  cr.CommentCount,
  coalesce(ec.CommentCountRecent, 0) AS RecentCommentCount,
  coalesce(tr.repl_count, 0) AS ReplyCount,
  coalesce(ts.tag_count, 0) AS TagParticipation,
  CASE
    WHEN cr.Score > 10 THEN 'Hot'
    WHEN cr.ViewCount > 1000 THEN 'Popular'
    ELSE 'New'
  END AS Tier
FROM complex_pred cr
LEFT JOIN top_repliers tr ON tr.PostId = cr.PostId
LEFT JOIN exists_recent_comments ec ON ec.PostId = cr.PostId
LEFT JOIN tag_stats ts ON ts.PostId = cr.PostId
WHERE
  cr.CreationDate > NOW() - INTERVAL '30 days'
  AND (cr.ViewCount + cr.Score * 2) > 15
ORDER BY Tier, cr.LastActivityDate DESC
LIMIT 100;