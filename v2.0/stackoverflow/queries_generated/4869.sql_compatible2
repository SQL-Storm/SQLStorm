WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS HistoryType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
      JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.UserId IS NOT NULL
      AND ph.Comment IS NOT NULL
      AND ph.Comment LIKE '%accepted%'
  ),
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(*) AS TotalPosts,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  UserEditStats AS (
    SELECT
      UserId,
      COUNT(DISTINCT PostId) AS EditedPostCount,
      MAX(CreationDate) AS LastEditDate
    FROM
      RankedPostEdits
    WHERE
      rn = 1
    GROUP BY
      UserId
  ),
  HotQuestions AS (
    SELECT
      Id
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND Score > (
        SELECT
          AVG(Score)
        FROM
          Posts
        WHERE
          PostTypeId = 1
      ) * 2
      AND ViewCount > 1000
      AND CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
  )
SELECT
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  COALESCE(upc.TotalPosts, 0) AS TotalPostsByUser,
  COALESCE(upc.QuestionCount, 0) AS QuestionCountByUser,
  COALESCE(upc.AnswerCount, 0) AS AnswerCountByUser,
  COALESCE(ues.EditedPostCount, 0) AS PostsEditedByThisUser,
  ues.LastEditDate AS UserLastEditTimestamp,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteCategory,
  (
    SELECT
      COUNT(*)
    FROM
      Badges b
    WHERE
      b.UserId = u.Id
      AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c
    WHERE
      c.UserId = u.Id
      AND c.Score > 5
  ) AS HighlyScoredComments,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        Posts p
      WHERE
        p.OwnerUserId = u.Id
        AND p.ClosedDate IS NOT NULL
    ) THEN 'Has Closed Posts'
    ELSE 'No Closed Posts'
  END AS ClosedPostStatus,
  CASE
    WHEN u.DisplayName LIKE '%[A-Z]%' THEN 'Contains Uppercase'
    ELSE 'No Uppercase'
  END AS DisplayNameCase,
  CASE
    WHEN u.AboutMe LIKE '%SQL%' OR u.AboutMe LIKE '%database%' THEN 'Mentions SQL/DB'
    ELSE 'No SQL/DB Mention'
  END AS AboutMeKeywords,
  hq.Id AS HotQuestionId
FROM
  Users u
  LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
  LEFT JOIN UserEditStats ues ON u.Id = ues.UserId
  LEFT JOIN HotQuestions hq ON hq.Id = hq.Id OR u.Id = hq.Id
WHERE
  u.Reputation > 1000
  AND u.DownVotes < 10
  AND u.Views > 500

UNION ALL

SELECT
  'Community User' AS DisplayName,
  0 AS Reputation,
  NULL AS UserCreationDate,
  COUNT(DISTINCT p.Id) AS TotalPostsByUser,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCountByUser,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCountByUser,
  COUNT(DISTINCT ph.PostId) AS PostsEditedByThisUser,
  MAX(ph.CreationDate) AS UserLastEditTimestamp,
  'Community Owned' AS WebsiteCategory,
  0 AS GoldBadgeCount,
  0 AS HighlyScoredComments,
  'N/A' AS ClosedPostStatus,
  'No Uppercase' AS DisplayNameCase,
  'N/A' AS AboutMeKeywords,
  NULL AS HotQuestionId
FROM
  Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
WHERE
  p.OwnerUserId = -1
  AND ph.UserId IS NULL
  AND pht.Name = 'Community Owned'
GROUP BY
  p.OwnerUserId

ORDER BY
  Reputation DESC,
  UserLastEditTimestamp DESC
LIMIT 100;