-- {"query": "4385.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1181}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      p.OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Posts p
      ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  RecentEditors AS (
    SELECT
      PostId,
      UserId AS EditorUserId,
      EditDate
    FROM RankedPostEdits
    WHERE
      rn = 1
  ),
  EditorEngagement AS (
    SELECT
      re.EditorUserId,
      COUNT(DISTINCT re.PostId) AS EditedPostCount,
      SUM(CASE WHEN p.OwnerUserId = re.EditorUserId THEN 1 ELSE 0 END) AS OwnEdits,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.ViewCount) AS MaxPostViews,
      SUM(CASE WHEN p.FavoriteCount > 0 THEN 1 ELSE 0 END) AS PostsFavorited,
      COUNT(DISTINCT ph.UserId) AS UniqueModeratorInteractions
    FROM RecentEditors re
    JOIN Posts p
      ON re.PostId = p.Id
    LEFT JOIN PostHistory ph
      ON p.Id = ph.PostId AND ph.UserId = re.EditorUserId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
    GROUP BY
      re.EditorUserId
  ),
  UserReputation AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate,
      u.DisplayName,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2
      ) AS SilverBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3
      ) AS BronzeBadges,
      u.WebsiteUrl
    FROM Users u
  )
SELECT
  ue.UserId,
  ue.DisplayName,
  ue.Reputation,
  ue.CreationDate,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ue.UserViews,
  ue.UserUpVotes,
  ue.UserDownVotes,
  COALESCE(ei.EditedPostCount, 0) AS TotalEditedPosts,
  COALESCE(ei.OwnEdits, 0) AS OwnEditsOnTheirPosts,
  COALESCE(ei.AvgPostScore, 0.0) AS AvgScoreOfEditedPosts,
  COALESCE(ei.MaxPostViews, 0) AS MaxViewsOfEditedPosts,
  COALESCE(ei.PostsFavorited, 0) AS EditedPostsFavorited,
  COALESCE(ei.UniqueModeratorInteractions, 0) AS UniqueModeratorInteractionsOnEditedPosts,
  CASE
    WHEN ue.Reputation > 100000 THEN 'High'
    WHEN ue.Reputation > 10000 THEN 'Medium'
    ELSE 'Low'
  END AS ReputationTier,
  CASE
    WHEN ue.CreationDate < (cast('2024-10-01' as date) - INTERVAL '5 year') THEN 'Veteran'
    WHEN ue.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Experienced'
    ELSE 'Newbie'
  END AS TenureStatus,
  LOWER(SUBSTRING(ue.DisplayName FROM 1 FOR 1)) AS FirstInitial,
  CASE
    WHEN ue.WebsiteUrl IS NOT NULL AND ue.WebsiteUrl <> '' THEN 'HasWebsite'
    ELSE 'NoWebsite'
  END AS WebsitePresence,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.UserId = ue.UserId AND c.Score > 5
  ) AS HighScoreCommentCount
FROM UserReputation ue
LEFT JOIN EditorEngagement ei
  ON ue.UserId = ei.EditorUserId
WHERE
  ue.Reputation > 100
  AND ue.UserUpVotes > ue.UserDownVotes * 2
  AND ue.DisplayName IS NOT NULL
  AND ue.DisplayName NOT LIKE '%[deleted]%'
ORDER BY
  ue.Reputation DESC,
  TotalEditedPosts DESC,
  ue.CreationDate ASC;