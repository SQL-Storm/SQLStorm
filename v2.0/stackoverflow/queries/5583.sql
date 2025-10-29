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
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.LastActivityDate DESC, p.Score DESC, p.ViewCount DESC
    ) AS rn_by_activity,
    DENSE_RANK() OVER (
      ORDER BY p.CreationDate DESC
    ) AS recency_rank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2,5)
),
CorrelatedStats AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    r.ParentId,
    r.AcceptedAnswerId,
    r.CommentCount,
    r.FavoriteCount,
    r.ContentLicense,
    r.Reputation,
    r.DisplayName,
    r.Location,
    r.Views,
    r.UpVotes,
    r.DownVotes,
    r.AccountId,
    r.rn_by_activity,
    r.recency_rank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId AND c.UserId IS NOT NULL) AS CommentersCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId AND pl.LinkTypeId = 3) AS DuplicateCount
  FROM RankedPosts r
),
Aggregated AS (
  SELECT
    cs.PostId,
    cs.PostTypeId,
    cs.Title,
    cs.Tags,
    cs.CreationDate,
    cs.Score,
    cs.ViewCount,
    cs.OwnerUserId,
    cs.LastActivityDate,
    cs.ParentId,
    cs.AcceptedAnswerId,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.ContentLicense,
    cs.Reputation,
    cs.DisplayName,
    cs.Location,
    cs.Views,
    cs.UpVotes,
    cs.DownVotes,
    cs.AccountId,
    cs.rn_by_activity,
    cs.recency_rank,
    cs.CommentersCount,
    cs.DuplicateCount,
    (cs.Score + COALESCE(cs.ViewCount,0) * 0.1
     + COALESCE(cs.CommentersCount,0) * 2
     + CASE WHEN cs.Location IS NOT NULL THEN 1 ELSE 0 END) AS CompositeScore,
    CASE
      WHEN (cs.Score + COALESCE(cs.ViewCount,0) * 0.1) > 0 THEN TRUE
      ELSE FALSE
    END AS IsPromotable
  FROM CorrelatedStats cs
)
SELECT
  a.PostId,
  a.PostTypeId,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.Score,
  a.ViewCount,
  a.OwnerUserId,
  a.LastActivityDate,
  a.ParentId,
  a.AcceptedAnswerId,
  a.CommentCount,
  a.FavoriteCount,
  a.ContentLicense,
  a.Reputation,
  a.DisplayName,
  a.Location,
  a.Views,
  a.UpVotes,
  a.DownVotes,
  a.AccountId,
  a.rn_by_activity,
  a.recency_rank,
  a.CommentersCount,
  a.DuplicateCount,
  a.CompositeScore,
  a.IsPromotable,
  le.Id AS LastEditorUserId,
  le.DisplayName AS LastEditorDisplayName,
  le.Reputation AS LastEditorReputation
FROM Aggregated a
LEFT JOIN Posts p2 ON a.PostId = p2.Id
LEFT JOIN Users le ON p2.LastEditorUserId = le.Id
WHERE a.IsPromotable = TRUE
  AND a.ViewCount > 0
ORDER BY a.CompositeScore DESC, a.LastActivityDate DESC
LIMIT 100;