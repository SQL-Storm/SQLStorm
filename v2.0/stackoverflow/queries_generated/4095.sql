-- {"query": "4095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2365} 

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
      DATEDIFF(DAY, p.CreationDate, GETDATE()) AS DaysSinceCreation,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 AND p.CreationDate >= DATEADD(day, -365, GETDATE())
  ),
  QuestionAnswers AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent,
      AVG(CAST(a.Score AS FLOAT)) AS AvgAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate,
      COUNT(CASE WHEN a.OwnerUserId IS NOT NULL THEN a.Id ELSE NULL END) AS AnswererCount
    FROM Posts AS a
    LEFT JOIN Posts AS p
      ON a.Id = p.AcceptedAnswerId
    WHERE
      a.PostTypeId = 2
    GROUP BY
      a.ParentId
  ),
  TopAnswerers AS (
    SELECT
      qa.QuestionId,
      STRING_AGG(ua.DisplayName, ', ') WITHIN GROUP (ORDER BY ua.Reputation DESC) AS TopAnswererNames,
      STRING_AGG(CAST(ua.Reputation AS VARCHAR), ', ') WITHIN GROUP (ORDER BY ua.Reputation DESC) AS TopAnswererReputations
    FROM QuestionAnswers AS qa
    JOIN Posts AS a
      ON qa.QuestionId = a.ParentId
    JOIN Users AS ua
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
    FROM Comments AS c
    WHERE
      EXISTS (
        SELECT
          1
        FROM Posts AS p
        WHERE
          p.Id = c.PostId AND p.PostTypeId = 1
      )
    GROUP BY
      c.PostId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      COUNT(p.Id) AS QuestionCount,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
      MAX(p.CreationDate) AS LastPostDate,
      AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore,
      SUM(p.ViewCount) AS TotalViewCount
    FROM Users AS u
    LEFT JOIN Posts AS p
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
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (
        2,
        5,
        8
      ) /* Body edits */
    GROUP BY
      ph.PostId
  ),
  PostTagAnalysis AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(DISTINCT t.TagName) AS DistinctTagCount,
      STRING_AGG(t.TagName, ',') AS AllTags,
      (
        SELECT
          COUNT(*)
        FROM STRING_SPLIT(p.Tags, '><')
        WHERE
          value LIKE '%net%'
      ) AS NetTagCount
    FROM Posts AS p
    LEFT JOIN Tags AS t
      ON t.TagName = ANY(
        SELECT
          value
        FROM STRING_SPLIT(p.Tags, '><')
      )
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.Tags
  ),
  RankedUsers AS (
    SELECT
      UserId,
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
  ISNULL(qa.AvgAnswerScore, 0) AS AverageAnswerScore,
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
    WHEN DATEDIFF(DAY, qa.LastAnswerDate, GETDATE()) < 7 THEN 'Recently Answered'
    ELSE 'Older Answers'
  END AS AnswerRecency,
  UPPER(SUBSTRING(rq.Title, 1, 3)) AS TitlePrefix,
  COALESCE(ta.TopAnswererNames, 'No specific answerers') AS TopAnswerers,
  ISNULL(rq.OwnerUserId, -999) AS OwnerUserIdNullCheck,
  DENSE_RANK() OVER (ORDER BY rq.QuestionScore DESC) AS ScoreRank
FROM RecentQuestions AS rq
LEFT JOIN QuestionAnswers AS qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN QuestionComments AS qc
  ON rq.QuestionId = qc.QuestionId
LEFT JOIN UserActivity AS ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN PostRevisionCounts AS prc
  ON rq.QuestionId = prc.PostId
LEFT JOIN PostTagAnalysis AS pta
  ON rq.QuestionId = pta.QuestionId
LEFT JOIN RankedUsers AS ru
  ON rq.OwnerUserId = ru.UserId
LEFT JOIN TopAnswerers AS ta
  ON rq.QuestionId = ta.QuestionId
WHERE
  rq.rn <= 1000
  AND rq.QuestionViewCount > 50
  AND (
    qa.AnswerCount IS NULL OR qa.AnswerCount > 0
  )
  AND rq.OwnerDisplayName IS NOT NULL
  AND LEFT(rq.Title, 1) <> '?'
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
  ISNULL(qa.AvgAnswerScore, 0) AS AverageAnswerScore,
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
    WHEN DATEDIFF(DAY, qa.LastAnswerDate, GETDATE()) < 7 THEN 'Recently Answered'
    ELSE 'Older Answers'
  END AS AnswerRecency,
  UPPER(SUBSTRING(rq.Title, 1, 3)) AS TitlePrefix,
  COALESCE(ta.TopAnswererNames, 'No specific answerers') AS TopAnswerers,
  ISNULL(rq.OwnerUserId, -999) AS OwnerUserIdNullCheck,
  DENSE_RANK() OVER (ORDER BY rq.QuestionScore DESC) AS ScoreRank
FROM RecentQuestions AS rq
JOIN QuestionAnswers AS qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN QuestionComments AS qc
  ON rq.QuestionId = qc.QuestionId
LEFT JOIN UserActivity AS ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN PostRevisionCounts AS prc
  ON rq.QuestionId = prc.PostId
LEFT JOIN PostTagAnalysis AS pta
  ON rq.QuestionId = pta.QuestionId
LEFT JOIN RankedUsers AS ru
  ON rq.OwnerUserId = ru.UserId
LEFT JOIN TopAnswerers AS ta
  ON rq.QuestionId = ta.QuestionId
WHERE
  rq.rn <= 1000
  AND rq.QuestionViewCount > 50
  AND qa.AnswerCount > 0
  AND rq.OwnerDisplayName IS NOT NULL
  AND LEFT(rq.Title, 1) = '?'
ORDER BY
  rq.QuestionScore DESC,
  rq.QuestionViewCount DESC;
