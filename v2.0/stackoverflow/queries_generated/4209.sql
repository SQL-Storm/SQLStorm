-- {"query": "4209.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1229} 

WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      u.DisplayName AS OwnerDisplayName,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-365 day')
  ),
  AnsweredQuestions AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(a.Id) AS NumberOfAnswers,
      SUM(a.Score) AS TotalAnswerScore,
      AVG(a.Score) AS AverageAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate,
      MAX(a.ViewCount) AS MaxAnswerViewCount,
      SUM(CASE WHEN a.Id = pq.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent
    FROM Posts AS p
    JOIN Posts AS a
      ON p.Id = a.ParentId
    LEFT JOIN Posts AS pq
      ON pq.Id = p.AcceptedAnswerId
    WHERE
      p.PostTypeId = 1
      AND a.PostTypeId = 2
    GROUP BY
      p.Id
  ),
  QuestionPerformance AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.Tags,
      rq.OwnerDisplayName,
      rq.QuestionCreationDate,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.QuestionViewCount,
      COALESCE(aq.NumberOfAnswers, 0) AS TotalAnswers,
      COALESCE(aq.TotalAnswerScore, 0) AS TotalAnswerScore,
      COALESCE(aq.AverageAnswerScore, 0.0) AS AverageAnswerScore,
      aq.LastAnswerDate,
      aq.IsAcceptedAnswerPresent,
      CASE
        WHEN aq.IsAcceptedAnswerPresent > 0 THEN 'Accepted'
        ELSE 'Not Accepted'
      END AS AcceptanceStatus,
      -- Complex Predicate with string manipulation and NULL logic
      CASE
        WHEN INSTR(rq.Tags, 'sql') > 0 AND rq.QuestionScore > 50 THEN 'SQL Expert Level'
        WHEN INSTR(rq.Tags, 'performance') > 0 AND rq.QuestionScore > 100 THEN 'Performance Guru'
        WHEN INSTR(rq.Tags, 'optimization') > 0 AND rq.QuestionScore > 75 THEN 'Optimization Master'
        WHEN rq.AnswerCount > 10 AND rq.QuestionScore > 20 THEN 'High Engagement'
        WHEN aq.LastAnswerDate IS NOT NULL AND DATE(aq.LastAnswerDate) >= DATE(rq.QuestionCreationDate, '+7 day') THEN 'Actively Answered'
        WHEN rq.FavoriteCount > 5 THEN 'Popular'
        WHEN rq.QuestionScore < 0 THEN 'Negative Score'
        ELSE 'Standard'
      END AS PerformanceTier,
      -- Window Function: Rank questions by score within their tag group
      RANK() OVER (PARTITION BY SUBSTRING(rq.Tags, 2, INSTR(rq.Tags, '>') - 2) ORDER BY rq.QuestionScore DESC) AS RankInTag
    FROM RecentQuestions AS rq
    LEFT JOIN AnsweredQuestions AS aq
      ON rq.QuestionId = aq.QuestionId
    WHERE
      rq.rn <= 1000 -- Limit to top 1000 recent questions for performance
  )
SELECT
  qp.QuestionId,
  qp.Title,
  qp.OwnerDisplayName,
  qp.QuestionCreationDate,
  qp.QuestionScore,
  qp.TotalAnswers,
  qp.TotalAnswerScore,
  qp.AverageAnswerScore,
  qp.AcceptanceStatus,
  qp.PerformanceTier,
  qp.RankInTag,
  -- Correlated Subquery to get the count of users who have commented on the question
  (
    SELECT
      COUNT(DISTINCT c.UserId)
    FROM Comments AS c
    WHERE
      c.PostId = qp.QuestionId
      AND c.UserId IS NOT NULL
      AND c.CreationDate >= qp.QuestionCreationDate
  ) AS DistinctCommenters,
  -- Set Operator: Union of posts that are questions or have been closed recently
  (
    SELECT
      'Question'
    FROM Posts AS p
    WHERE
      p.Id = qp.QuestionId
      AND p.PostTypeId = 1
    UNION ALL
    SELECT
      'Closed Question'
    FROM Posts AS p
    WHERE
      p.Id = qp.QuestionId
      AND p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
      AND p.ClosedDate >= DATE('now', '-30 day')
  ) AS QuestionStatusFlag
FROM QuestionPerformance AS qp
WHERE
  qp.RankInTag <= 5 -- Select top 5 questions within their primary tag (simplistic tag extraction)
ORDER BY
  qp.QuestionScore DESC,
  qp.TotalAnswers DESC;
