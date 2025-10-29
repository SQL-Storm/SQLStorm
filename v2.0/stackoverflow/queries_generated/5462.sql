-- {"query": "5462.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1171} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditDate,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    NULL AS ReplyDensity,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn_post
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS rn_user
  FROM Users u
  WHERE u.Reputation > 0
),
TagStat AS (
  SELECT
    t.TagName,
    t.Count,
    t.WikiPostId,
    t.ExcerptPostId,
    (t.Count * 1.0 / NULLIF((SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1), 0)) AS Popularity
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    CASE
      WHEN v.VoteTypeId = 2 THEN 'UpMod'
      WHEN v.VoteTypeId = 3 THEN 'DownMod'
      WHEN v.VoteTypeId = 10 THEN 'Deletion'
      WHEN v.VoteTypeId = 11 THEN 'Undeletion'
      ELSE 'Other'
    END AS VoteLabel
  FROM Votes v
  WHERE v.CreationDate > NOW() - INTERVAL '60 days'
),
Linked AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkType,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
RecentBounties AS (
  SELECT
    v.PostId,
    v.BountyAmount,
    v.CreationDate,
    v.UserId
  FROM Votes v
  WHERE v.VoteTypeId = 8 -- BountyStart
)
SELECT
  rp.PostId,
  rp.PostTypeId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  ru.DisplayName AS OwnerDisplayName,
  ru.Reputation AS OwnerReputation,
  ru.LastAccessDate AS OwnerLastAccess,
  rp.LastEditDate,
  rp.LastActivityDate,
  (
    SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId
  ) AS CommentCount,
  (
    SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2
  ) AS UpVotesForPost,
  (
    SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.PostId AND v.BountyAmount IS NOT NULL
  ) AS AvgBounty,
  t Popularity AS TagPopularity,
  rc.Name AS CloseReason,
  ra.Name AS AcceptedAnswerType,
  STRING_AGG(CONCAT(lp.Name, '->', rp.Title), ' | ') FILTER (WHERE lp.PostId IS NOT NULL) AS LinkPreview,
  ARRAY_AGG(DISTINCT lb.Name) FILTER (WHERE lb.Name IS NOT NULL) AS BadgesOnOwner,
  (SELECT json_agg(DISTINCT u2.DisplayName) FROM Users u2 JOIN Posts p2 ON p2.OwnerUserId = u2.Id WHERE p2.Id = rp.PostId) AS OwnersOnPost
FROM RankedPosts rp
LEFT JOIN Users ru ON rp.OwnerUserId = ru.Id
LEFT JOIN PostHistory ph ON ph.PostId = rp.PostId
LEFT JOIN CloseReasonTypes rc ON CAST(ph.Comment AS VARCHAR) IS NOT NULL AND ph.PostHistoryTypeId = 10
LEFT JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN (SELECT DISTINCT Name FROM Badges WHERE UserId = rp.OwnerUserId) lb ON 1=1
LEFT JOIN (SELECT NULL) AS t ON 1=1
LEFT JOIN TopContributors tc ON rp.OwnerUserId = tc.UserId AND tc.rn_user = 1
LEFT JOIN TagStat ts ON 1=1
LEFT JOIN Linked lp ON rp.PostId = lp.PostId
LEFT JOIN (SELECT Name FROM PostHistory phh WHERE phh.PostHistoryTypeId = 10 LIMIT 1) ra ON 1=1
WHERE rp.rn_post = 1
GROUP BY
  rp.PostId, rp.PostTypeId, rp.Title, rp.Tags, rp.CreationDate, rp.Score, rp.ViewCount,
  rp.OwnerUserId, ru.DisplayName, ru.Reputation, ru.LastAccessDate, rp.LastEditDate,
  rp.LastActivityDate, rc.Name, ra.Name, t.Popularity
ORDER BY rp.Score DESC, rp.ViewCount DESC
LIMIT 100;