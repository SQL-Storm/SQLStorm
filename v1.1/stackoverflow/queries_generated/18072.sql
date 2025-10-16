-- {"query": "18072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 882} 

WITH
  RecentQuestions AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-30 day')
  ),
  HighScoringAnswers AS (
    SELECT
      p.ParentId,
      COUNT(p.Id) AS NumHighScoringAnswers,
      AVG(p.Score) AS AvgAnswerScore
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 AND p.Score >= 5
    GROUP BY
      p.ParentId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEditCount,
      MAX(u.Reputation) AS MaxReputation
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagContributions AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS TagQuestionCount,
      SUM(CASE WHEN p.OwnerUserId = t.OwnerUserId THEN 1 ELSE 0 END) AS OwnerPostsForTag
    FROM Tags AS t
    JOIN Posts AS p
      ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY
      t.TagName,
      t.OwnerUserId
  )
SELECT
  rq.Title AS QuestionTitle,
  rq.Tags,
  ua.DisplayName AS QuestionOwner,
  COALESCE(hsa.NumHighScoringAnswers, 0) AS NumberOfHighScoringAnswers,
  COALESCE(hsa.AvgAnswerScore, 0.0) AS AverageAnswerScore,
  ua.PostHistoryCount,
  ua.BodyEditCount,
  COALESCE(tc.TagQuestionCount, 0) AS TotalTagQuestions,
  tc.OwnerPostsForTag,
  CASE
    WHEN rq.Score > 100 THEN 'Highly Scored'
    WHEN rq.AnswerCount > 20 THEN 'Popular'
    WHEN ua.Reputation > 10000 THEN 'Experienced User'
    ELSE 'Standard'
  END AS QuestionCategory,
  'Users who create or contribute to this tag' AS TaggingInfo,
  CASE
    WHEN ua.MaxReputation IS NULL THEN 'No reputation data available'
    WHEN ua.MaxReputation BETWEEN 0 AND 1000 THEN 'Novice'
    WHEN ua.MaxReputation BETWEEN 1001 AND 10000 THEN 'Intermediate'
    ELSE 'Expert'
  END AS UserReputationLevel,
  CAST(rq.CreationDate AS DATE) AS QuestionDate
FROM RecentQuestions AS rq
LEFT JOIN HighScoringAnswers AS hsa
  ON rq.Id = hsa.ParentId
LEFT JOIN UserActivity AS ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN TagContributions AS tc
  ON tc.TagName = SUBSTRING(rq.Tags FROM 2 FOR POSITION('><' IN rq.Tags) - 2) AND tc.OwnerUserId = rq.OwnerUserId
WHERE
  rq.rn <= 100
  AND rq.Score > 0
  AND ua.UserId IS NOT NULL
ORDER BY
  rq.Score DESC,
  rq.AnswerCount DESC,
  rq.CreationDate ASC;
