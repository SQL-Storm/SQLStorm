WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserActivitySummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgQuestionScore,
      MAX(p.CreationDate) AS LatestActivityDate
    FROM
      Users AS u
      LEFT JOIN Posts AS p
        ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
    HAVING
      COUNT(p.Id) > 0
  ),
  HotQuestions AS (
    SELECT
      Id,
      Title,
      Score,
      AnswerCount,
      ViewCount,
      CreationDate,
      ROW_NUMBER() OVER (ORDER BY Score DESC, AnswerCount DESC, ViewCount DESC) AS HotRank
    FROM
      Posts
    WHERE
      PostTypeId = 1 AND CommunityOwnedDate IS NULL AND ClosedDate IS NULL
  ),
  PostsWithCommunityEdits AS (
    SELECT
      p.Id,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.LastActivityDate,
      CASE WHEN COUNT(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 ELSE NULL END) > 0 THEN 1 ELSE 0 END AS IsCommunityOwned,
      COUNT(CASE WHEN ph.UserId = -1 THEN 1 ELSE NULL END) AS CommunityEditCount
    FROM
      Posts AS p
      LEFT JOIN PostHistory AS ph
        ON p.Id = ph.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.LastActivityDate
  )
SELECT
  hq.HotRank,
  hq.Title AS HotQuestionTitle,
  hq.Score AS HotQuestionScore,
  uas.DisplayName AS TopContributorName,
  uas.Reputation AS TopContributorReputation,
  pce.IsCommunityOwned,
  pce.CommunityEditCount,
  ROUND(AVG(CAST(LENGTH(pce.Title) AS NUMERIC)), 2) AS AvgHotQuestionTitleLength,
  COUNT(CASE WHEN rpe.rn = 1 THEN 1 ELSE NULL END) AS TotalEditsByTopContributorsToHotQuestions
FROM
  HotQuestions AS hq
JOIN
  PostsWithCommunityEdits AS pce
  ON hq.Id = pce.Id
LEFT JOIN
  UserActivitySummary AS uas
  ON pce.OwnerUserId = uas.UserId
    AND uas.LatestActivityDate BETWEEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY) AND CAST('2024-10-01 12:34:56' AS TIMESTAMP)
LEFT JOIN
  RankedPostEdits AS rpe
  ON hq.Id = rpe.PostId AND rpe.rn = 1 AND rpe.UserId = uas.UserId
WHERE
  hq.HotRank <= 100 AND uas.Reputation >= 10000
GROUP BY
  hq.HotRank,
  hq.Title,
  hq.Score,
  uas.DisplayName,
  uas.Reputation,
  pce.IsCommunityOwned,
  pce.CommunityEditCount
HAVING
  COUNT(rpe.UserId) > 0
ORDER BY
  hq.HotRank;