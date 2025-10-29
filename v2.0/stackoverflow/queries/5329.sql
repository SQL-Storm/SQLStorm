-- {"query": "5329.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 655}
WITH
recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
tag_expansion AS (
  SELECT
    rp.Id AS PostId,
    unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags) - 2), '> <')) AS Tag
  FROM recent_posts rp
  WHERE rp.Tags IS NOT NULL
),
correlated_history AS (
  SELECT
    rp.Id AS PostId,
    AVG(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1.0 ELSE 0 END) AS CloseVoteRatio,
    MAX(vs.CreationDate) AS LastVoteDate
  FROM recent_posts rp
  LEFT JOIN PostHistory ph ON ph.PostId = rp.Id
  LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
  LEFT JOIN Votes v ON v.PostId = rp.Id
  LEFT JOIN Votes vs ON vs.PostId = rp.Id AND vs.VoteTypeId = 2
  GROUP BY rp.Id
),
complex_metrics AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    COALESCE(vt.Name, 'Unknown') AS PrimaryVoteType,
    CASE
      WHEN rp.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id)
      ELSE 0
    END AS CommentCount,
    CASE
      WHEN rp.ParentId IS NULL THEN 1 ELSE 0
    END AS IsQuestionRoot,
    ca.LastVoteDate,
    ca.CloseVoteRatio,
    te.Tag
  FROM recent_posts rp
  LEFT JOIN Users u ON u.Id = rp.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = rp.Id AND v.VoteTypeId = 2
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  LEFT JOIN correlated_history ca ON ca.PostId = rp.Id
  LEFT JOIN tag_expansion te ON te.PostId = rp.Id
)
SELECT
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.CreationDate,
  cm.LastActivityDate,
  cm.Score,
  cm.ViewCount,
  cm.PrimaryVoteType,
  cm.CommentCount,
  cm.IsQuestionRoot,
  cm.LastVoteDate,
  cm.CloseVoteRatio,
  cm.Tag
FROM complex_metrics cm
WHERE cm.Tag IS NOT NULL
  AND cm.Score > 0
ORDER BY cm.LastActivityDate DESC, cm.Score DESC
LIMIT 100;