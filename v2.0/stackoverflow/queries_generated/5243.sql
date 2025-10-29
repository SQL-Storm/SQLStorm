-- {"query": "5243.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 823} 
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
  WHERE p.PostTypeId = 1 -- Questions
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
    CAST(NULL AS int) AS RelatedPostId
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
    CASE
      WHEN vl.RelatedPostId IS NULL THEN NULL
      ELSE vl.RelatedPostId
    END AS RelatedPostId
  FROM Posts p
  JOIN TagHotArticles th ON p.ParentId = th.PostId
  LEFT JOIN LATERAL (
    SELECT hl.RelatedPostId
    FROM PostLinks hl
    WHERE hl.PostId = p.Id AND hl.LinkTypeId = 1
  ) vl ON true
  WHERE p.PostTypeId = 1
),
Agg AS (
  SELECT
    ph.PostId,
    ph.Title,
    ph.CreationDate,
    ph.ViewCount,
    ph.Score,
    ph.OwnerUserId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ph.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ph.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ph.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ph.PostId) AS LinkCount,
    (SELECT MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) FROM Votes v WHERE v.PostId = ph.PostId) AS LastUpVoteDate,
    (SELECT STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN CAST(v.BountyAmount AS varchar) END, ',') 
       FROM Votes v WHERE v.PostId = ph.PostId AND v.VoteTypeId = 2) AS UpVoteHistory
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
  COALESCE(b.Date, NULL) AS BadgeDate
FROM Agg a
JOIN Posts p ON p.Id = a.PostId
LEFT JOIN Users u ON u.Id = a.OwnerUserId
LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
LEFT JOIN LATERAL (
  SELECT bh.Date
  FROM Badges bh
  WHERE bh.UserId = u.Id
  ORDER BY bh.Date DESC
  LIMIT 1
) b ON true
WHERE a.UpVotes > 5
  AND (a.DownVotes < a.UpVotes OR a.UpVotes IS NULL)
  AND (a.ViewCount > 100 OR a.CommentCount > 0)
ORDER BY a.Score DESC, a.ViewCount DESC
LIMIT 100;