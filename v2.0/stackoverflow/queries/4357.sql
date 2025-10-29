-- {"query": "4357.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1063}
WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    pht.Name AS HistoryTypeName,
    ph.Comment,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  JOIN PostHistoryTypes pht
    ON ph.PostHistoryTypeId = pht.Id
  WHERE
    ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4, 5, 6)
), UserPostActivity AS (
  SELECT
    p.OwnerUserId,
    COUNT(DISTINCT p.Id) AS TotalPostsOwned,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(p.Score) AS AveragePostScore,
    MAX(p.CreationDate) AS LatestPostDate
  FROM Posts p
  WHERE
    p.OwnerUserId IS NOT NULL
  GROUP BY
    p.OwnerUserId
), LatestUserEdit AS (
  SELECT
    rpe.UserId,
    rpe.PostId AS LastEditedPostId,
    rpe.CreationDate AS LastEditDate,
    rpe.HistoryTypeName AS LastEditType
  FROM RankedPostEdits rpe
  WHERE
    rpe.rn = 1
), UserReputationAndBadges AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadges,
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadges,
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadges
  FROM Users u
)
SELECT
  upa.OwnerUserId,
  MAX(ureb.Reputation) AS MaxReputation,
  SUM(upa.TotalPostsOwned) AS TotalPostsEverOwned,
  AVG(upa.AveragePostScore) AS GlobalAverageScoreAcrossOwnedPosts,
  COUNT(CASE WHEN ureb.GoldBadges > 0 THEN 1 END) AS UsersWithGoldBadges,
  COUNT(CASE WHEN ureb.SilverBadges > 0 THEN 1 END) AS UsersWithSilverBadges,
  COUNT(CASE WHEN ureb.BronzeBadges > 0 THEN 1 END) AS UsersWithBronzeBadges,
  COUNT(DISTINCT lue.LastEditedPostId) AS DistinctPostsEditedByThisUser,
  MAX(lue.LastEditDate) AS MostRecentEditByThisUser,
  STRING_AGG(DISTINCT lue.LastEditType, ', ') AS TypesOfLastEdits,
  CASE
    WHEN ureb.UserCreationDate < (cast('2024-10-01' as date) - INTERVAL '5 years') AND upa.AnswerCount > 1000 THEN 'Veteran High-Answerer'
    WHEN ureb.Reputation > 50000 AND upa.QuestionCount > 500 THEN 'Established High-Volume Author'
    WHEN upa.LatestPostDate < (cast('2024-10-01' as date) - INTERVAL '1 year') AND ureb.Reputation < 1000 THEN 'Inactive Low-Rep User'
    ELSE 'Standard User Profile'
  END AS UserProfileCategory,
  (
    SELECT COUNT(DISTINCT c.Id)
    FROM Comments c
    WHERE
      c.UserId = upa.OwnerUserId AND c.CreationDate > (cast('2024-10-01' as date) - INTERVAL '30 days')
  ) AS RecentCommentsCount
FROM UserPostActivity upa
LEFT JOIN UserReputationAndBadges ureb
  ON upa.OwnerUserId = ureb.UserId
LEFT JOIN LatestUserEdit lue
  ON upa.OwnerUserId = lue.UserId
WHERE
  COALESCE(ureb.Reputation, 0) > 100 OR upa.TotalPostsOwned > 50
GROUP BY
  upa.OwnerUserId,
  ureb.Reputation,
  upa.TotalPostsOwned,
  upa.AveragePostScore,
  ureb.GoldBadges,
  ureb.SilverBadges,
  ureb.BronzeBadges,
  ureb.UserCreationDate,
  upa.AnswerCount,
  upa.QuestionCount,
  upa.LatestPostDate
HAVING
  COUNT(DISTINCT lue.LastEditedPostId) > 0 OR upa.AnswerCount > 0
ORDER BY
  MaxReputation DESC,
  TotalPostsEverOwned DESC;