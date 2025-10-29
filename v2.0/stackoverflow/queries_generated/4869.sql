-- {"query": "4869.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1220} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS HistoryType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
      JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
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
      AND CreationDate > DATE('now', '-30 day')
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
      Badges AS b
    WHERE
      b.UserId = u.Id
      AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM
      Comments AS c
    WHERE
      c.UserId = u.Id
      AND c.Score > 5
  ) AS HighlyScoredComments,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        Posts AS p
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
  Users AS u
  LEFT OUTER JOIN UserPostCounts AS upc ON u.Id = upc.OwnerUserId
  LEFT OUTER JOIN UserEditStats AS ues ON u.Id = ues.UserId
  LEFT OUTER JOIN HotQuestions AS hq ON u.Id = hq.Id
WHERE
  u.Reputation > 1000
  AND u.DownVotes < 10
  AND u.Views > 500
UNION
SELECT
  'Community User' AS DisplayName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
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
  Posts AS p
  LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
  LEFT JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
WHERE
  p.OwnerUserId = -1
  AND ph.UserId IS NULL
  AND pht.Name = 'Community Owned'
GROUP BY
  p.OwnerUserId
ORDER BY
  u.Reputation DESC,
  UserLastEditTimestamp DESC
LIMIT 100;
