WITH RECURSIVE
TagHotArticles AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagHierarchy AS (
  SELECT
    th.PostId,
    th.Title,
    th.CreationDate,
    th.Score,
    th.ViewCount,
    th.Tags,
    th.OwnerUserId,
    th.rn,
    CAST(NULL AS INTEGER) AS RelatedPostId
  FROM TagHotArticles th
  UNION ALL
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    th.rn,
    vl.RelatedPostId
  FROM Posts p
  JOIN TagHotArticles th ON p.ParentId = th.PostId
  LEFT JOIN (
    SELECT hl.PostId, hl.RelatedPostId
    FROM PostLinks hl
    WHERE hl.LinkTypeId = 1
  ) vl ON vl.PostId = p.Id
  WHERE p.PostTypeId = 1
),
Agg AS (
  SELECT
    ph.Id AS PostId,
    ph.Title,
    ph.CreationDate,
    ph.ViewCount,
    ph.Score,
    ph.OwnerUserId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ph.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ph.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ph.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ph.Id) AS LinkCount,
    (SELECT MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) FROM Votes v WHERE v.PostId = ph.Id) AS LastUpVoteDate,
    (SELECT STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN CAST(v.BountyAmount AS VARCHAR) END, ',') 
       FROM Votes v WHERE v.PostId = ph.Id AND v.VoteTypeId = 2) AS UpVoteHistory
  FROM Posts ph
  WHERE ph.PostTypeId = 1
)
SELECT
  a.PostId,
  a.Title,
  a.CreationDate,
  a.ViewCount,
  a.Score,
  a.CommentCount,
  a.UpVotes,
  a.DownVotes,
  a.LinkCount,
  a.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.LastAccessDate,
  u.AccountId,
  p.Tags,
  p.Body,
  p.Title AS QuestionTitleAlias,
  b_latest.Date AS BadgeDate
FROM Agg a
JOIN Posts p ON p.Id = a.PostId
LEFT JOIN Users u ON u.Id = a.OwnerUserId
LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
LEFT JOIN (
  SELECT bh.UserId, bh.Date
  FROM Badges bh
  WHERE bh.Date IS NOT NULL
  ORDER BY bh.UserId, bh.Date DESC
) b_latest_full ON b_latest_full.UserId = u.Id
LEFT JOIN LATERAL (
  SELECT bh.Date
  FROM Badges bh
  WHERE bh.UserId = u.Id
  ORDER BY bh.Date DESC
  LIMIT 1
) b_latest ON true
WHERE a.UpVotes > 5
  AND (a.DownVotes < a.UpVotes OR a.UpVotes IS NULL)
  AND (a.ViewCount > 100 OR a.CommentCount > 0)
ORDER BY a.Score DESC, a.ViewCount DESC
LIMIT 100;