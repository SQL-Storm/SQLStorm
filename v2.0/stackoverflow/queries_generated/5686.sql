-- {"query": "5686.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1026} 
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
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation AS UserReputation,
    u.DisplayName AS UserDisplayName,
    u.Location AS UserLocation,
    u.AccountId AS UserAccountId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_stats AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    p.Id AS PostId,
    p.Score,
    p.ViewCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
composite AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.UserReputation,
    rq.UserDisplayName,
    rq.UserLocation,
    rq.UserAccountId,
    ts.tag AS TopTag,
    ts.Score AS PostScoreForTag,
    ts.ViewCount AS TagPostViews
  FROM recent_questions rq
  LEFT JOIN (
    SELECT
      tag,
      MAX(Score) AS Score
    FROM tag_stats
    GROUP BY tag
  ) AS t ON true
  LEFT JOIN tag_stats ts ON ts.tag = (SELECT tag FROM tag_stats WHERE tag = ts.tag LIMIT 1)
),
recent_activity AS (
  SELECT
    c.PostId,
    c.Text AS CommentText,
    c.CreationDate AS CommentDate,
    c.UserDisplayName AS CommentUser,
    c.Score AS CommentScore
  FROM Comments c
  WHERE c.CreationDate >= NOW() - INTERVAL '14 days'
),
cross_links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.CreationDate >= NOW() - INTERVAL '60 days'
),
votes_summary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(v.BountyAmount) AS MaxBounty
  FROM Votes v
  GROUP BY v.PostId
),
risk_score AS (
  SELECT
    r.PostId,
    (0.5 * COALESCE(vs.UpVotes,0) - 0.25 * COALESCE(vs.DownVotes,0)
     + 0.2 * COALESCE(r.Score,0)
     + 0.1 * COALESCE(r.ViewCount,0)
     + 0.05 * COALESCE(vs.MaxBounty,0)
    ) AS BenchmarkScore
  FROM (
    SELECT Id AS PostId, Score, ViewCount
    FROM Posts
    WHERE PostTypeId = 1
  ) r
  LEFT JOIN votes_summary vs ON vs.PostId = r.PostId
)
SELECT
  cr.PostId,
  cr.Title,
  cr.Tags,
  cr.CreationDate,
  cr.Score,
  cr.ViewCount,
  cr.OwnerUserId,
  cr.UserReputation,
  cr.UserDisplayName,
  cr.UserLocation,
  cr.UserAccountId,
  ct.TopTag,
  ct.PostScoreForTag,
  ct.TagPostViews,
  ra.CommentDate AS RecentCommentDate,
  ra.CommentUser AS RecentCommentUser,
  ra.CommentScore AS RecentCommentScore,
  cl.RelatedPostId,
  cl.LinkTypeName,
  vs.UpVotes,
  vs.DownVotes,
  COALESCE(rs.BenchmarkScore, 0) AS BenchmarkScore
FROM composite cr
LEFT JOIN composite ct ON ct.PostId = cr.PostId AND ct.TopTag IS NOT NULL
LEFT JOIN recent_activity ra ON ra.PostId = cr.PostId
LEFT JOIN cross_links cl ON cl.PostId = cr.PostId
LEFT JOIN votes_summary vs ON vs.PostId = cr.PostId
LEFT JOIN risk_score rs ON rs.PostId = cr.PostId
WHERE cr.ViewCount > 0
  AND (rs.BenchmarkScore IS NULL OR rs.BenchmarkScore > -10)
ORDER BY BenchmarkScore DESC NULLS LAST, cr.CreationDate DESC
LIMIT 100;