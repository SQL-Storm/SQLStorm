WITH CTE AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    u.Reputation,
    u.Views,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE NULL END AS AcceptedAnswerId,
    CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE NULL END AS ParentId,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS OwnerPostRank,
    RANK() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS TagRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
Interactions AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
PostVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
  FROM Votes v
  GROUP BY v.PostId
)
SELECT
  c.Id,
  c.PostTypeId,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.Title,
  c.Tags,
  c.OwnerUserId,
  c.Reputation,
  c.Views,
  c.UserUpVotes AS UpVotes,
  c.UserDownVotes AS DownVotes,
  CASE WHEN c.PostTypeId = 1 THEN c.AcceptedAnswerId ELSE NULL END AS AcceptedAnswerId,
  CASE WHEN c.PostTypeId = 2 THEN c.ParentId ELSE NULL END AS ParentId,
  c.OwnerPostRank,
  c.TagRank,
  i.CommentCount,
  pv.UpVotes AS VoteUpCount,
  pv.DownVotes AS VoteDownCount,
  pv.Favorites AS FavoriteCount
FROM CTE c
LEFT JOIN Interactions i ON c.Id = i.PostId
LEFT JOIN PostVotes pv ON c.Id = pv.PostId
WHERE c.OwnerPostRank <= 5
  AND c.TagRank <= 3
GROUP BY
  c.Id,
  c.PostTypeId,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.Title,
  c.Tags,
  c.OwnerUserId,
  c.Reputation,
  c.Views,
  c.UserUpVotes,
  c.UserDownVotes,
  c.AcceptedAnswerId,
  c.ParentId,
  c.OwnerPostRank,
  c.TagRank,
  i.CommentCount,
  pv.UpVotes,
  pv.DownVotes,
  pv.Favorites
ORDER BY
  c.Score DESC,
  c.ViewCount DESC
LIMIT 100;