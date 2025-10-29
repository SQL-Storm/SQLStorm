WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount AS QuestionAnswerCount,
      p.Score AS QuestionScore,
      COALESCE(p.FavoriteCount, 0) AS QuestionFavoriteCount,
      COALESCE(p.CommentCount, 0) AS QuestionCommentCount,
      u.DisplayName AS OwnerDisplayName,
      CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 day')
  ),
  QuestionAnswers AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent,
      AVG(CAST(a.Score AS DOUBLE PRECISION)) AS AvgAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate,
      COUNT(CASE WHEN a.OwnerUserId IS NOT NULL THEN a.Id ELSE NULL END) AS AnswererCount
    FROM Posts a
    LEFT JOIN Posts p
      ON a.Id = p.AcceptedAnswerId
    WHERE
      a.PostTypeId = 2
    GROUP BY
      a.ParentId
  ),
  TopAnswerers AS (
    SELECT
      qa.QuestionId,
      STRING_AGG(ua.DisplayName, ', ' ORDER BY ua.Reputation DESC) AS TopAnswererNames,
      STRING_AGG(CAST(ua.Reputation AS TEXT), ', ' ORDER BY ua.Reputation DESC) AS TopAnswererReputations
    FROM QuestionAnswers qa
    JOIN Posts a
      ON qa.QuestionId = a.ParentId
    JOIN Users ua
      ON a.OwnerUserId = ua.Id
    WHERE
      a.PostTypeId = 2
    GROUP BY
      qa.QuestionId
  ),
  QuestionComments AS (
    SELECT
      c.PostId AS QuestionId,
      COUNT(c.Id) AS CommentCount
    FROM Comments c
    WHERE
      EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.Id = c.PostId AND p.PostTypeId = 1
      )
    GROUP BY
      c.PostId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
      COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
      MAX(p.CreationDate) AS LastPostDate,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AvgPostScore,
      SUM(COALESCE(p.ViewCount,0)) AS TotalViewCount
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    WHERE
      u.Id <> -1
    GROUP BY
      u.Id
  ),
  PostRevisionCounts AS (
    SELECT
      ph.PostId,
      COUNT(ph.Id) AS RevisionCount
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (2, 5, 8)
    GROUP BY
      ph.PostId
  ),
  PostTagAnalysis AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(DISTINCT t.TagName) AS DistinctTagCount,
      STRING_AGG(t.TagName, ',') AS AllTags,
      (
        SELECT COUNT(*)
        FROM UNNEST(
          regexp_split_to_array(trim(both '<>' FROM p.Tags), '><')
        ) AS s(value)
        WHERE value LIKE '%net%'
      ) AS NetTagCount
    FROM Posts p
    LEFT JOIN LATERAL (
      SELECT unnest(regexp_split_to_array(trim(both '<>' FROM p.Tags), '><')) AS TagName
    ) t ON TRUE
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.Tags
  ),
  RankedUsers AS (
    SELECT
      Id AS UserId,
      Reputation,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
    WHERE
      Id <> -1
  )

SELECT
  rq.QuestionId,
  rq.Title,
  rq.OwnerDisplayName,
  rq.QuestionCreationDate,
  rq.DaysSinceCreation,
  rq.QuestionViewCount,
  rq.QuestionAnswerCount,
  COALESCE(qa.AnswerCount, 0) AS ActualAnswerCount,
  rq.QuestionScore,
  rq.QuestionFavoriteCount,
  rq.QuestionCommentCount,
  COALESCE(qc.CommentCount, 0) AS ActualCommentCount,
  COALESCE(qa.IsAcceptedAnswerPresent, 0) AS AcceptedAnswerExists,
  COALESCE(qa.AvgAnswerScore, 0) AS AverageAnswerScore,
  ua.QuestionCount AS OwnerQuestionCount,
  ua.AnswerCount AS OwnerAnswerCount,
  ua.TotalViewCount AS OwnerTotalViewCount,
  COALESCE(prc.RevisionCount, 0) AS RevisionCount,
  pta.DistinctTagCount,
  pta.NetTagCount,
  ru.ReputationRank AS OwnerReputationRank,
  CASE
    WHEN rq.QuestionViewCount > 10000 THEN 'High Traffic'
    WHEN rq.QuestionViewCount > 1000 THEN 'Medium Traffic'
    ELSE 'Low Traffic'
  END AS TrafficCategory,
  CASE
    WHEN qa.LastAnswerDate IS NOT NULL AND (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - qa.LastAnswerDate)) / 86400) < 7 THEN 'Recently Answered'
    ELSE 'Older Answers'
  END AS AnswerRecency,
  UPPER(SUBSTRING(rq.Title FROM 1 FOR 3)) AS TitlePrefix,
  COALESCE(ta.TopAnswererNames, 'No specific answerers') AS TopAnswerers,
  COALESCE(rq.OwnerUserId, -999) AS OwnerUserIdNullCheck,
  DENSE_RANK() OVER (ORDER BY rq.QuestionScore DESC) AS ScoreRank
FROM RecentQuestions rq
LEFT JOIN QuestionAnswers qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN QuestionComments qc
  ON rq.QuestionId = qc.QuestionId
LEFT JOIN UserActivity ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN PostRevisionCounts prc
  ON rq.QuestionId = prc.PostId
LEFT JOIN PostTagAnalysis pta
  ON rq.QuestionId = pta.QuestionId
LEFT JOIN RankedUsers ru
  ON rq.OwnerUserId = ru.UserId
LEFT JOIN TopAnswerers ta
  ON rq.QuestionId = ta.QuestionId
WHERE
  rq.rn <= 1000
  AND rq.QuestionViewCount > 50
  AND (qa.AnswerCount IS NULL OR qa.AnswerCount > 0)
  AND rq.OwnerDisplayName IS NOT NULL
  AND SUBSTRING(rq.Title FROM 1 FOR 1) <> '?'

UNION

SELECT
  rq.QuestionId,
  rq.Title,
  rq.OwnerDisplayName,
  rq.QuestionCreationDate,
  rq.DaysSinceCreation,
  rq.QuestionViewCount,
  rq.QuestionAnswerCount,
  COALESCE(qa.AnswerCount, 0) AS ActualAnswerCount,
  rq.QuestionScore,
  rq.QuestionFavoriteCount,
  rq.QuestionCommentCount,
  COALESCE(qc.CommentCount, 0) AS ActualCommentCount,
  COALESCE(qa.IsAcceptedAnswerPresent, 0) AS AcceptedAnswerExists,
  COALESCE(qa.AvgAnswerScore, 0) AS AverageAnswerScore,
  ua.QuestionCount AS OwnerQuestionCount,
  ua.AnswerCount AS OwnerAnswerCount,
  ua.TotalViewCount AS OwnerTotalViewCount,
  COALESCE(prc.RevisionCount, 0) AS RevisionCount,
  pta.DistinctTagCount,
  pta.NetTagCount,
  ru.ReputationRank AS OwnerReputationRank,
  CASE
    WHEN rq.QuestionViewCount > 10000 THEN 'High Traffic'
    WHEN rq.QuestionViewCount > 1000 THEN 'Medium Traffic'
    ELSE 'Low Traffic'
  END AS TrafficCategory,
  CASE
    WHEN qa.LastAnswerDate IS NOT NULL AND (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - qa.LastAnswerDate)) / 86400) < 7 THEN 'Recently Answered'
    ELSE 'Older Answers'
  END AS AnswerRecency,
  UPPER(SUBSTRING(rq.Title FROM 1 FOR 3)) AS TitlePrefix,
  COALESCE(ta.TopAnswererNames, 'No specific answerers') AS TopAnswerers,
  COALESCE(rq.OwnerUserId, -999) AS OwnerUserIdNullCheck,
  DENSE_RANK() OVER (ORDER BY rq.QuestionScore DESC) AS ScoreRank
FROM RecentQuestions rq
JOIN QuestionAnswers qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN QuestionComments qc
  ON rq.QuestionId = qc.QuestionId
LEFT JOIN UserActivity ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN PostRevisionCounts prc
  ON rq.QuestionId = prc.PostId
LEFT JOIN PostTagAnalysis pta
  ON rq.QuestionId = pta.QuestionId
LEFT JOIN RankedUsers ru
  ON rq.OwnerUserId = ru.UserId
LEFT JOIN TopAnswerers ta
  ON rq.QuestionId = ta.QuestionId
WHERE
  rq.rn <= 1000
  AND rq.QuestionViewCount > 50
  AND qa.AnswerCount > 0
  AND rq.OwnerDisplayName IS NOT NULL
  AND SUBSTRING(rq.Title FROM 1 FOR 1) = '?'
ORDER BY
  QuestionScore DESC,
  QuestionViewCount DESC;