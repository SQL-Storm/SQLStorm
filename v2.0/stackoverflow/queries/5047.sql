-- {"query": "5047.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 707} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
TopPostThemes AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.LastActivityDate,
    -- derive a faux "topic score" from tags length and activity
    (CHAR_LENGTH(rp.Tags) * 0.3 + EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - rp.LastActivityDate)) * -0.000001) AS theme_score
  FROM RecentActivePosts rp
  WHERE rp.rn = 1
),
CorrelatedStats AS (
  SELECT
    tpt.PostId,
    tpt.Title,
    tpt.LastActivityDate,
    tpt.theme_score,
    v1.UserId AS VoterA_Id,
    v1.CreationDate AS VoterA_VoteDate,
    v1.BountyAmount AS VoterA_Bounty,
    v2.UserId AS VoterB_Id,
    v2.CreationDate AS VoterB_VoteDate,
    v2.BountyAmount AS VoterB_Bounty,
    -- count related links as a performance-like metric
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = tpt.PostId OR pl.RelatedPostId = tpt.PostId) AS LinkCount
  FROM TopPostThemes tpt
  LEFT JOIN Votes v1 ON v1.PostId = tpt.PostId AND v1.VoteTypeId = 2
  LEFT JOIN Votes v2 ON v2.PostId = tpt.PostId AND v2.VoteTypeId = 14
  WHERE tpt.theme_score > (SELECT AVG(theme_score) FROM TopPostThemes)
),
EnrichedPosts AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.LastActivityDate,
    cs.theme_score,
    cs.LinkCount,
    -- compute a pseudo-engagement metric combining views, scores and votes
    (p.ViewCount * 0.6 + p.Score * 1.2 + COALESCE(v1.BountyAmount,0) * 0.0) AS engagement_score
  FROM CorrelatedStats cs
  LEFT JOIN Posts p ON p.Id = cs.PostId
  LEFT JOIN Votes v1 ON v1.PostId = cs.PostId AND v1.VoteTypeId = 2
)
SELECT
  ep.PostId,
  ep.Title,
  ep.LastActivityDate,
  ep.theme_score,
  ep.LinkCount,
  ep.engagement_score,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.CreationDate AS OwnerCreationDate
FROM EnrichedPosts ep
JOIN Posts p ON p.Id = ep.PostId
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE u.Id IS NOT NULL
ORDER BY ep.engagement_score DESC, ep.theme_score DESC
LIMIT 100;