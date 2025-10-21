WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      pht.Name AS HistoryTypeName,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
      AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.CreationDate >= DATE '2023-01-01'
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.FavoriteCount,
      (
        SELECT
          COUNT(*) 
        FROM Comments AS c
        WHERE
          c.PostId = p.Id
      ) AS CommentCount,
      (
        SELECT
          COUNT(*) 
        FROM Votes AS v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 2
      ) AS UpVoteCount,
      (
        SELECT
          COUNT(*) 
        FROM Votes AS v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 3
      ) AS DownVoteCount
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 -- Questions only
  )
SELECT
  pe.PostId,
  pe.Title,
  uc.DisplayName AS OwnerDisplayName,
  uc.UserId AS OwnerUserId,
  uc.QuestionCount,
  uc.AnswerCount,
  uc.GoldBadgeCount,
  uc.SilverBadgeCount,
  uc.BronzeBadgeCount,
  uc.AvgPostScore AS AverageScore,
  uc.LastPostDate,
  pe.Score,
  pe.ViewCount,
  pe.FavoriteCount,
  pe.CommentCount,
  pe.UpVoteCount,
  pe.DownVoteCount,
  rpe.CreationDate AS LastEditDate,
  rpe.HistoryTypeName AS LastEditType,
  CASE
    WHEN pe.FavoriteCount > 100 AND pe.UpVoteCount > 500 THEN 'Highly Engaged'
    WHEN pe.ViewCount > 10000 THEN 'Popular'
    WHEN pe.CommentCount > 20 OR (SELECT COUNT(*) FROM Posts AS p2 WHERE p2.OwnerUserId = pe.OwnerUserId AND p2.PostTypeId = 1) > 10 THEN 'Discussed'
    ELSE 'Standard'
  END AS EngagementCategory,
  CASE
    WHEN uc.LastPostDate < DATE '2022-01-01' THEN 'Inactive Contributor'
    ELSE 'Active Contributor'
  END AS ContributorStatus,
  CASE
    WHEN pe.FavoriteCount IS NULL THEN 0
    ELSE pe.FavoriteCount
  END AS SafeFavoriteCount,
  SUBSTRING(pe.Title FROM 1 FOR 50) AS TitlePrefix,
  LENGTH(pe.Title) AS TitleLength,
  (pe.UpVoteCount - pe.DownVoteCount) AS NetVotes
FROM PostEngagement AS pe
JOIN UserContribution AS uc
  ON pe.OwnerUserId = uc.UserId
LEFT JOIN RankedPostEdits AS rpe
  ON pe.PostId = rpe.PostId AND rpe.rn = 1
WHERE
  pe.Score > 10
  AND uc.LastPostDate IS NOT NULL
  AND uc.LastPostDate >= DATE '2023-01-01'
ORDER BY
  pe.Score DESC,
  pe.ViewCount DESC;