WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS PostCount
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  TopUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      upc.PostCount,
      ROW_NUMBER() OVER (
        ORDER BY
          u.Reputation DESC,
          upc.PostCount DESC
      ) AS rn
    FROM
      Users AS u
      JOIN UserPostCounts AS upc ON u.Id = upc.OwnerUserId
    WHERE
      u.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1' YEAR)
      AND u.Views > 1000
  ),
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.OwnerUserId AS QuestionOwnerUserId,
      pt.Name AS PostTypeName,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      COALESCE(p.CommentCount, 0) AS CommentCount,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS QuestionStatus
    FROM
      Posts AS p
      JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId = 1
  ),
  AnswerDetails AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswerOwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.ParentId
        ORDER BY
          p.Score DESC,
          p.CreationDate ASC
      ) AS rn_score
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 2
  ),
  UserActivity AS (
    SELECT
      u.Id,
      u.DisplayName,
      COUNT(DISTINCT ph.Id) AS HistoryEdits,
      MAX(ph.CreationDate) AS LastEditDate
    FROM
      Users AS u
      JOIN PostHistory AS ph ON u.Id = ph.UserId
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  QandAInfo AS (
    SELECT
      qd.QuestionId,
      qd.Title,
      qd.QuestionCreationDate,
      qd.QuestionOwnerUserId,
      tu.DisplayName AS QuestionOwnerDisplayName,
      qd.AnswerCount,
      qd.CommentCount,
      qd.FavoriteCount,
      qd.QuestionStatus,
      ad.AnswerId,
      ad.AnswerOwnerUserId,
      tu2.DisplayName AS AnswerOwnerDisplayName,
      ad.AnswerCreationDate,
      ad.AnswerScore
    FROM
      QuestionDetails AS qd
      LEFT JOIN AnswerDetails AS ad ON qd.QuestionId = ad.QuestionId
      AND ad.rn_score = 1
      LEFT JOIN Users AS tu ON qd.QuestionOwnerUserId = tu.Id
      LEFT JOIN Users AS tu2 ON ad.AnswerOwnerUserId = tu2.Id
    WHERE
      qd.QuestionCreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '30' DAY) AND cast('2024-10-01' as date)
  )
SELECT
  qi.QuestionId,
  qi.Title,
  qi.QuestionCreationDate,
  qi.QuestionOwnerDisplayName,
  qi.AnswerCount,
  qi.CommentCount,
  qi.FavoriteCount,
  qi.QuestionStatus,
  COALESCE(qi.AnswerId, -1) AS AnswerId,
  COALESCE(qi.AnswerOwnerDisplayName, 'Community') AS AnswerOwnerDisplayName,
  qi.AnswerCreationDate,
  qi.AnswerScore,
  ua.HistoryEdits,
  CASE
    WHEN ua.LastEditDate IS NULL THEN 'Never Edited'
    WHEN qi.QuestionCreationDate = ua.LastEditDate THEN 'Edited on Creation'
    ELSE SUBSTR(CAST(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ua.LastEditDate)) / 86400.0 AS TEXT), 1, 5) || ' days since last edit'
  END AS EditStatus
FROM
  QandAInfo AS qi
  LEFT JOIN UserActivity AS ua ON qi.QuestionOwnerUserId = ua.Id
WHERE
  qi.AnswerScore > 5
  OR qi.AnswerCount = 0
UNION
SELECT
  NULL AS QuestionId,
  '--- Top User Snapshot ---' AS Title,
  NULL AS QuestionCreationDate,
  tu.DisplayName AS QuestionOwnerDisplayName,
  tu.Reputation,
  tu.PostCount,
  NULL AS FavoriteCount,
  NULL AS QuestionStatus,
  NULL AS AnswerId,
  NULL AS AnswerOwnerDisplayName,
  NULL AS AnswerCreationDate,
  NULL AS AnswerScore,
  NULL AS HistoryEdits,
  NULL AS EditStatus
FROM
  TopUsers AS tu
WHERE
  tu.rn <= 5
ORDER BY
  QuestionOwnerDisplayName,
  AnswerScore DESC;