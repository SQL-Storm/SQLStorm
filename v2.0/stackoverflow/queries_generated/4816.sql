-- {"query": "4816.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1243} 

WITH
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      CreationDate,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC, CreationDate ASC) AS rn
    FROM
      Users
    WHERE
      Reputation >= 10000
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      hr.DisplayName AS OwnerDisplayName,
      CASE
        WHEN hr.rn <= 5 THEN 'Top Contributor'
        ELSE 'Active User'
      END AS UserTier
    FROM
      Posts AS p
      LEFT OUTER JOIN HighReputationUsers AS hr ON p.OwnerUserId = hr.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-1 year')
      AND p.Title LIKE '%performance%'
  ),
  QuestionAnswers AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS AnswerCount,
      AVG(p.Score) AS AvgAnswerScore,
      MAX(p.CreationDate) AS LastAnswerDate
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  QuestionsWithAnswerDetails AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.OwnerUserId,
      rq.CreationDate AS QuestionCreationDate,
      rq.Score AS QuestionScore,
      rq.ViewCount,
      rq.AnswerCount AS DirectAnswerCount,
      COALESCE(qad.AnswerCount, 0) AS TotalAnswers,
      COALESCE(qad.AvgAnswerScore, 0) AS AvgAnswerScore,
      qad.LastAnswerDate,
      rq.UserTier,
      CASE
        WHEN rq.QuestionScore > 50 AND COALESCE(qad.AnswerCount, 0) > 10 THEN 'High Engagement'
        WHEN rq.QuestionScore < 0 AND COALESCE(qad.AnswerCount, 0) = 0 THEN 'Unanswered & Poorly Received'
        ELSE 'Standard'
      END AS EngagementCategory,
      (rq.ViewCount * 1.0 / NULLIF(rq.AnswerCount, 0)) AS ViewsPerAnswer
    FROM
      RecentQuestions AS rq
      LEFT OUTER JOIN QuestionAnswers AS qad ON rq.QuestionId = qad.QuestionId
  ),
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
  FinalResult AS (
    SELECT
      qwad.QuestionId,
      qwad.Title,
      qwad.QuestionCreationDate,
      qwad.QuestionScore,
      qwad.ViewCount,
      qwad.TotalAnswers,
      qwad.AvgAnswerScore,
      qwad.LastAnswerDate,
      qwad.UserTier,
      qwad.EngagementCategory,
      qwad.ViewsPerAnswer,
      upc.PostCount AS OwnerTotalPosts,
      CASE
        WHEN qwad.LastAnswerDate IS NOT NULL THEN JULIANDAY(qwad.LastAnswerDate) - JULIANDAY(qwad.QuestionCreationDate)
        ELSE NULL
      END AS TimeToFirstOrLastAnswer,
      (
        SELECT
          COUNT(c.Id)
        FROM
          Comments AS c
        WHERE
          c.PostId = qwad.QuestionId
          AND c.CreationDate BETWEEN qwad.QuestionCreationDate AND qwad.LastAnswerDate
      ) AS CommentsOnQuestion
    FROM
      QuestionsWithAnswerDetails AS qwad
      LEFT OUTER JOIN UserPostCounts AS upc ON qwad.OwnerUserId = upc.OwnerUserId
  )
SELECT
  fr.QuestionId,
  fr.Title,
  fr.QuestionCreationDate,
  fr.QuestionScore,
  fr.ViewCount,
  fr.TotalAnswers,
  CAST(fr.AvgAnswerScore AS DECIMAL(5, 2)) AS FormattedAvgAnswerScore,
  fr.LastAnswerDate,
  fr.UserTier,
  fr.EngagementCategory,
  CAST(fr.ViewsPerAnswer AS DECIMAL(10, 2)) AS FormattedViewsPerAnswer,
  fr.OwnerTotalPosts,
  fr.TimeToFirstOrLastAnswer,
  fr.CommentsOnQuestion,
  LOWER(SUBSTR(fr.Title, 1, INSTR(fr.Title, ' '))) AS FirstWordOfTitle,
  CASE
    WHEN fr.LastAnswerDate IS NULL THEN 'No Answers'
    WHEN fr.LastAnswerDate >= DATE('now', '-7 days') THEN 'Recent'
    ELSE 'Older'
  END AS AnswerRecency
FROM
  FinalResult AS fr
WHERE
  fr.OwnerTotalPosts > 10
  AND fr.AvgAnswerScore > 0
  AND fr.TimeToFirstOrLastAnswer IS NOT NULL
  AND fr.CommentsOnQuestion BETWEEN 1 AND 5
ORDER BY
  fr.QuestionScore DESC,
  fr.ViewCount DESC,
  fr.TotalAnswers DESC
LIMIT 100;
