-- {"query": "5793.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 910}
WITH RecentHot AS (
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
    p.ParentId,
    p.PostTypeId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate > (CAST('2024-10-01' AS DATE) - INTERVAL '180 days')
),
HotTagRank AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName ASC) AS tag_rank
  FROM Tags t
  WHERE t.Count > 100
),
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    CASE
      WHEN u.Reputation >= 10000 THEN 'Legend'
      WHEN u.Reputation >= 1000 THEN 'Enthusiast'
      ELSE 'Inactive'
    END AS UserTier
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
CrossLinks AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
CommentStats AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
RecentVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
)
SELECT
  rp.PostId,
  rp.Title,
  rp.Tags,
  rp.CreationDate AS PostCreationDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  au.UserId,
  au.DisplayName AS OwnerDisplayNameLive,
  au.Reputation,
  au.UserTier,
  rva.UpVotes,
  rva.DownVotes,
  cs.CommentCount,
  htr.tag_rank AS HotTagRank,
  rva.LastVoteDate,
  (rp.Score * 1.0) / NULLIF(rp.ViewCount, 0) AS ScorePerView,
  -- aggregate related post ids
  ARRAY_AGG(DISTINCT cl.RelatedPostId) FILTER (WHERE cl.RelatedPostId IS NOT NULL) AS RelatedPostIds
FROM RecentHot rp
LEFT JOIN ActiveUsers au ON rp.OwnerUserId = au.UserId
LEFT JOIN RecentVotes rva ON rp.PostId = rva.PostId
LEFT JOIN CommentStats cs ON rp.PostId = cs.PostId
LEFT JOIN CrossLinks cl ON rp.PostId = cl.PostId
-- approximate tag relation: join each tag name to rows where tag appears as substring in Tags
LEFT JOIN HotTagRank htr ON rp.Tags IS NOT NULL AND POSITION(htr.TagName IN rp.Tags) > 0
GROUP BY
  rp.PostId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.LastActivityDate,
  au.UserId,
  au.DisplayName,
  au.Reputation,
  au.UserTier,
  rva.UpVotes,
  rva.DownVotes,
  cs.CommentCount,
  htr.tag_rank,
  rva.LastVoteDate
ORDER BY rp.LastActivityDate DESC
LIMIT 100;