-- {"query": "5716.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 857} 
WITH recent_bounties AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    v.VoteTypeId,
    v.UserId AS VoterUserId,
    v.CreationDate AS VoteDate,
    b.Date AS BadgeDate,
    b.Name AS BadgeName,
    u.Reputation,
    u.DisplayName AS UserDisplayName,
    LAST_VALUE(u.Reputation) OVER (PARTITION BY p.Id ORDER BY b.Date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastReputation
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8 -- BountyStart
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
tag_metrics AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.Tags LIKE '%' || t.TagName || '%' AND p2.PostTypeId = 1) AS TaggedQuestionCount,
    (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.Tags LIKE '%' || t.TagName || '%' AND p3.PostTypeId = 1) AS AvgTagScore
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
complex_filter AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    COALESCE(COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2), 0) AS UpVotes,
    COALESCE(COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3), 0) AS DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.OwnerUserId IS NOT NULL
    AND p.CreationDate >= NOW() - INTERVAL '2 years'
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.Tags, c.CommentCount
)
SELECT
  cf.Id AS PostId,
  cf.Title,
  up.DisplayName AS Owner,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.Score,
  cf.ViewCount,
  cf.Tags,
  cf.CommentCount,
  cf.UpVotes,
  cf.DownVotes,
  rb.BadgeName,
  rb.BadgeDate,
  rb.Reputation,
  rb.LastReputation,
  tm.TagName,
  tm.Count AS TagCount,
  tm.TaggedQuestionCount,
  tm.AvgTagScore,
  -- windowed metric: running total of views per user over last 365 days
  SUM(cf.ViewCount) OVER (PARTITION BY cf.OwnerUserId ORDER BY cf.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningViews
FROM complex_filter cf
LEFT JOIN recent_bounties rb ON rb.PostId = cf.Id
LEFT JOIN Users up ON up.Id = cf.OwnerUserId
LEFT JOIN tag_metrics tm ON POSITION(tm.TagName IN cf.Tags) > 0
WHERE cf.rn = 1
ORDER BY cf.CreationDate DESC, cf.ViewCount DESC
LIMIT 100;