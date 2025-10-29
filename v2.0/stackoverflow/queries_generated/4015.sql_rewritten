-- {"query": "4015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1178} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AverageViewCount,
      MAX(p.FavoriteCount) AS MaxFavoriteCount,
      (
        SELECT
          COUNT(*)
        FROM
          Comments AS c
        WHERE
          c.UserId = p.OwnerUserId
      ) AS CommentCount
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  AggregatedPostData AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.FavoriteCount,
      pt.Name AS PostTypeName,
      COALESCE(u.DisplayName, p.OwnerDisplayName) AS DisplayName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            PostLinks AS pl
          WHERE
            pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate Link Type
        ),
        0
      ) AS DuplicateLinkCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            PostHistory AS ph
          WHERE
            ph.PostId = p.Id AND ph.PostHistoryTypeId = 19 -- Question Protected
        ),
        0
      ) AS ProtectionCount
    FROM
      Posts AS p
      JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE
      p.CreationDate >= '2023-01-01'
      AND p.PostTypeId IN (1, 2) -- Question, Answer
  )
SELECT
  apd.PostId,
  apd.PostTypeName,
  apd.DisplayName,
  apd.CreationDate,
  apd.Score,
  apd.ViewCount,
  apd.FavoriteCount,
  apd.IsClosed,
  apd.DuplicateLinkCount,
  apd.ProtectionCount,
  rpe.CreationDate AS LastEditDate,
  uc.PostCount AS UserTotalPosts,
  uc.TotalScore AS UserTotalScore,
  uc.AverageViewCount AS UserAverageViewCount,
  uc.MaxFavoriteCount AS UserMaxFavoriteCount,
  uc.CommentCount AS UserTotalComments,
  CASE
    WHEN apd.OwnerUserId = 1 THEN 'Community'
    WHEN apd.OwnerUserId = -1 THEN 'DeletedUser'
    ELSE 'RegisteredUser'
  END AS UserStatus,
  SUBSTRING(apd.DisplayName, 1, 3) AS DisplayNamePrefix,
  CASE
    WHEN apd.Score > 100 THEN 'HighScore'
    WHEN apd.Score BETWEEN 10 AND 100 THEN 'MidScore'
    ELSE 'LowScore'
  END AS ScoreCategory,
  COALESCE(apd.FavoriteCount, 0) AS NonNullFavoriteCount
FROM
  AggregatedPostData AS apd
  LEFT JOIN RankedPostEdits AS rpe ON apd.PostId = rpe.PostId AND rpe.rn = 1
  LEFT JOIN UserContribution AS uc ON apd.OwnerUserId = uc.OwnerUserId
WHERE
  (
    apd.ViewCount > 1000 OR apd.Score > 50
  )
  AND apd.DisplayName NOT LIKE '%test%'
  AND apd.DisplayName IS NOT NULL
UNION ALL
SELECT
  NULL,
  'Summary',
  'Total',
  MIN(apd.CreationDate),
  SUM(apd.Score),
  AVG(apd.ViewCount),
  SUM(apd.FavoriteCount),
  SUM(apd.IsClosed),
  SUM(apd.DuplicateLinkCount),
  SUM(apd.ProtectionCount),
  NULL,
  SUM(uc.PostCount),
  SUM(uc.TotalScore),
  AVG(uc.AverageViewCount),
  MAX(uc.MaxFavoriteCount),
  SUM(uc.CommentCount),
  NULL,
  NULL,
  NULL,
  NULL
FROM
  AggregatedPostData AS apd
  LEFT JOIN UserContribution AS uc ON apd.OwnerUserId = uc.OwnerUserId
WHERE
  apd.PostTypeId = 1;