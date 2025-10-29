-- {"query": "5128.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1097} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC NULLS LAST,
        p.ViewCount DESC NULLS LAST,
        p.LastActivityDate DESC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= TIMESTAMP '2020-01-01'
    AND p.LastActivityDate >= TIMESTAMP '2020-01-01'
),
Aggs AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    u.Reputation,
    u.DisplayName,
    EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = rp.OwnerUserId
        AND b.Date >= TIMESTAMP '2020-01-01'
    ) AS HasRecentBadges,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
  FROM RankedPosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  GROUP BY
    rp.PostId, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount,
    rp.Tags, rp.OwnerUserId, rp.LastActivityDate, rp.PostTypeId, rp.ParentId,
    rp.AcceptedAnswerId, rp.CommentCount, rp.FavoriteCount, rp.ContentLicense,
    u.Reputation, u.DisplayName
),
Windowed AS (
  SELECT
    a.*,
    SUM(a.UpVotes - a.DownVotes) OVER (
      PARTITION BY a.PostTypeId
      ORDER BY a.Score DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeNetVotes,
    MAX(a.Reputation) OVER (PARTITION BY a.OwnerUserId) AS MaxReputationByOwner,
    COUNT(DISTINCTCASE WHEN a.HasRecentBadges THEN 1 END) OVER () AS BadgePresenceWindow
  FROM Aggs a
),
CorrelatedTexts AS (
  SELECT
    w.PostId,
    w.Title,
    w.CreationDate,
    w.Score,
    w.ViewCount,
    w.Tags,
    w.OwnerUserId,
    w.LastActivityDate,
    w.PostTypeId,
    w.ParentId,
    w.AcceptedAnswerId,
    w.CommentCount,
    w.FavoriteCount,
    w.ContentLicense,
    w.Reputation,
    w.DisplayName,
    w.HasRecentBadges,
    w.UpVotes,
    w.DownVotes,
    w.CumulativeNetVotes,
    w.MaxReputationByOwner,
    w.BadgePresenceWindow,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = w.PostId) AS CommentCountTotal,
    (SELECT STRING_AGG(CONCAT(c.UserDisplayName, ':', c.Text), ' | ') 
     FROM PostHistory ph
     WHERE ph.PostId = w.PostId
       AND ph.CreationDate BETWEEN w.CreationDate AND w.LastActivityDate
    ) AS RevisionTrail
  FROM Windowed w
)
SELECT
  ct.PostId,
  ct.Title,
  ct.CreationDate,
  ct.LastActivityDate,
  ct.Score,
  ct.ViewCount,
  ct.Tags,
  CASE
    WHEN ct.PostTypeId = 1 THEN 'Question'
    WHEN ct.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostTypeName,
  ct.OwnerUserId,
  ct.DisplayName,
  ct.Reputation,
  ct.UpVotes,
  ct.DownVotes,
  ct.CommentCount,
  ct.CommentCountTotal,
  ct.FavoriteCount,
  ct.ContentLicense,
  ct.ParentId,
  ct.AcceptedAnswerId,
  ct.MaxReputationByOwner,
  ct.CumulativeNetVotes,
  ct.HasRecentBadges AS HasBadges,
  ct.RevisionTrail
FROM CorrelatedTexts ct
LEFT JOIN Users u ON ct.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON pl.PostId = ct.PostId
LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = ct.PostId
WHERE
  ct.CumulativeNetVotes IS NOT NULL
  AND (ct.Score > 0 OR ct.ViewCount > 100)
ORDER BY ct.LastActivityDate DESC
LIMIT 200;