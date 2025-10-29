-- {"query": "4510.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2385} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
  ),
  LatestPostEdits AS (
    SELECT
      rph.PostId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 1 THEN rph.CreationDate ELSE NULL END) AS InitialTitleDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 2 THEN rph.CreationDate ELSE NULL END) AS InitialBodyDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 3 THEN rph.CreationDate ELSE NULL END) AS InitialTagsDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.CreationDate ELSE NULL END) AS LatestTitleEditDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.CreationDate ELSE NULL END) AS LatestBodyEditDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 6 THEN rph.CreationDate ELSE NULL END) AS LatestTagsEditDate,
      MAX(CASE WHEN rph.PostHistoryTypeId = 1 THEN rph.UserId ELSE NULL END) AS InitialTitleUserId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 2 THEN rph.UserId ELSE NULL END) AS InitialBodyUserId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 3 THEN rph.UserId ELSE NULL END) AS InitialTagsUserId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.UserId ELSE NULL END) AS LatestTitleEditUserId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.UserId ELSE NULL END) AS LatestBodyEditUserId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 6 THEN rph.UserId ELSE NULL END) AS LatestTagsEditUserId
    FROM RankedPostHistory AS rph
    WHERE
      rph.rn = 1
    GROUP BY
      rph.PostId
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(p.ViewCount) AS TotalViewCount,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LastPostCreationDate,
      STRING_AGG(p.Title, ' | ') WITHIN GROUP (
        ORDER BY
          p.CreationDate
      ) AS AllPostTitles
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.PostTypeId = 1
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeCounts AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadgeCount,
      COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadgeCount,
      COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadgeCount
    FROM Badges AS b
    GROUP BY
      b.UserId
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate AS PostLastActivityDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount AS PostAnswerCount,
  p.CommentCount AS PostCommentCount,
  p.FavoriteCount AS PostFavoriteCount,
  lpe.InitialTitleDate,
  lpe.InitialBodyDate,
  lpe.InitialTagsDate,
  lpe.LatestTitleEditDate,
  lpe.LatestBodyEditDate,
  lpe.LatestTagsEditDate,
  lpe.InitialTitleUserId,
  lpe.InitialBodyUserId,
  lpe.InitialTagsUserId,
  lpe.LatestTitleEditUserId,
  lpe.LatestBodyEditUserId,
  lpe.LatestTagsEditUserId,
  upa.PostCount AS OwnerPostCount,
  upa.TotalViewCount AS OwnerTotalViewCount,
  upa.AverageScore AS OwnerAverageScore,
  upa.LastPostCreationDate AS OwnerLastPostCreationDate,
  SUBSTRING(upa.AllPostTitles, 1, 100) AS PartialOwnerPostTitles,
  COALESCE(ubc.GoldBadgeCount, 0) AS OwnerGoldBadges,
  COALESCE(ubc.SilverBadgeCount, 0) AS OwnerSilverBadges,
  COALESCE(ubc.BronzeBadgeCount, 0) AS OwnerBronzeBadges,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN u.Reputation > 100000 THEN 'Legendary'
    WHEN u.Reputation > 50000 THEN 'High Reputation'
    WHEN u.Reputation > 10000 THEN 'Mid Reputation'
    ELSE 'Low Reputation'
  END AS UserReputationLevel,
  COALESCE(
    (
      SELECT
        MAX(c.CreationDate)
      FROM Comments AS c
      WHERE
        c.PostId = p.Id AND c.UserId = p.OwnerUserId
    ),
    p.CreationDate
  ) AS LastCommentByOwnerDate,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = p.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN LatestPostEdits AS lpe
  ON p.Id = lpe.PostId
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserPostActivity AS upa
  ON p.OwnerUserId = upa.OwnerUserId
LEFT JOIN UserBadgeCounts AS ubc
  ON p.OwnerUserId = ubc.UserId
WHERE
  p.PostTypeId = 1
  AND p.CreationDate >= '2023-01-01'
  AND (
    p.Title LIKE '%SQL%' OR p.Tags LIKE '%sql%'
  )
  AND (
    u.DisplayName IS NOT NULL OR u.Location IS NOT NULL
  )
  AND COALESCE(p.FavoriteCount, 0) > 10
UNION
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate AS PostLastActivityDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount AS PostAnswerCount,
  p.CommentCount AS PostCommentCount,
  p.FavoriteCount AS PostFavoriteCount,
  lpe.InitialTitleDate,
  lpe.InitialBodyDate,
  lpe.InitialTagsDate,
  lpe.LatestTitleEditDate,
  lpe.LatestBodyEditDate,
  lpe.LatestTagsEditDate,
  lpe.InitialTitleUserId,
  lpe.InitialBodyUserId,
  lpe.InitialTagsUserId,
  lpe.LatestTitleEditUserId,
  lpe.LatestBodyEditUserId,
  lpe.LatestTagsEditUserId,
  upa.PostCount AS OwnerPostCount,
  upa.TotalViewCount AS OwnerTotalViewCount,
  upa.AverageScore AS OwnerAverageScore,
  upa.LastPostCreationDate AS OwnerLastPostCreationDate,
  SUBSTRING(upa.AllPostTitles, 1, 100) AS PartialOwnerPostTitles,
  COALESCE(ubc.GoldBadgeCount, 0) AS OwnerGoldBadges,
  COALESCE(ubc.SilverBadgeCount, 0) AS OwnerSilverBadges,
  COALESCE(ubc.BronzeBadgeCount, 0) AS OwnerBronzeBadges,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN u.Reputation > 100000 THEN 'Legendary'
    WHEN u.Reputation > 50000 THEN 'High Reputation'
    WHEN u.Reputation > 10000 THEN 'Mid Reputation'
    ELSE 'Low Reputation'
  END AS UserReputationLevel,
  COALESCE(
    (
      SELECT
        MAX(c.CreationDate)
      FROM Comments AS c
      WHERE
        c.PostId = p.Id AND c.UserId = p.OwnerUserId
    ),
    p.CreationDate
  ) AS LastCommentByOwnerDate,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = p.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN LatestPostEdits AS lpe
  ON p.Id = lpe.PostId
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserPostActivity AS upa
  ON p.OwnerUserId = upa.OwnerUserId
LEFT JOIN UserBadgeCounts AS ubc
  ON p.OwnerUserId = ubc.UserId
WHERE
  p.PostTypeId = 2
  AND p.CreationDate >= '2023-01-01'
  AND (
    p.Body LIKE '%performance%' OR p.Text LIKE '%benchmark%'
  )
  AND (
    u.DisplayName IS NOT NULL OR u.Location IS NOT NULL
  )
  AND COALESCE(p.Score, 0) > 5;
