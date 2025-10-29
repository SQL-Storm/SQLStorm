-- {"query": "5882.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 786} 
WITH recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    u.DisplayName AS VoterName,
    u.Reputation AS VoterRep
  FROM Votes v
  JOIN Users u ON v.UserId = u.Id
  WHERE v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
top_post_tags AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_stats AS (
  SELECT
    t.Tag,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM top_post_tags t
  CROSS JOIN LATERAL (SELECT * FROM Posts p WHERE p.Id = t.PostId) AS p
  GROUP BY t.Tag
),
complex_filter AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.CreationDate,
    p.FavoriteCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastEditorUserId,
    (CASE WHEN p.Score > 0 THEN TRUE ELSE FALSE END) AS PositiveScoreFlag,
    (CASE WHEN p.ViewCount > 1000 THEN 'Heavy' ELSE 'Light' END) AS ViewTier,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountFromComments
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
  WHERE
    p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
    AND EXISTS (
      SELECT 1
      FROM Votes v2
      WHERE v2.PostId = p.Id
        AND v2.VoteTypeId = 2
        AND v2.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
    )
)
SELECT
  cf.PostId,
  cf.Title,
  cf.Score,
  cf.ViewCount,
  cf.LastActivityDate,
  cf.OwnerUserId,
  cf.Tags,
  cf.CreationDate,
  cf.FavoriteCount,
  cf.CommentCount,
  cf.AnswerCount,
  cf.LastEditorUserId,
  cf.PositiveScoreFlag,
  cf.ViewTier,
  cf.CommentCountFromComments,
  rt.VoterName AS LastCommenter,
  rt.VoterRep AS LastCommenterRep,
  ts.PostCount AS TagPostCount,
  ts.AvgScore AS TagAvgScore,
  ts.TotalViews AS TagTotalViews,
  ts.LastActive AS TagLastActive
FROM complex_filter cf
LEFT JOIN recent_votes rv ON rv.PostId = cf.PostId
LEFT JOIN (
  SELECT DISTINCT ON (PostId)
    PostId,
    UserId,
    CreationDate,
    VoterName,
    VoterRep
  FROM recent_votes
  ORDER BY PostId, CreationDate DESC
) rt ON rt.PostId = cf.PostId
LEFT JOIN tag_stats ts ON true
ORDER BY cf.LastActivityDate DESC
LIMIT 100;