WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate > (cast('2024-10-01' as date) - INTERVAL '1 year')
  ),
  UserQuestionStats AS (
    SELECT
      rq.OwnerUserId,
      COUNT(rq.QuestionId) AS TotalRecentQuestions,
      SUM(rq.Score) AS TotalQuestionScore,
      AVG(CAST(rq.AnswerCount AS DOUBLE PRECISION)) AS AvgAnswersPerQuestion,
      MAX(rq.FavoriteCount) AS MaxFavoriteCount
    FROM RecentQuestions AS rq
    GROUP BY
      rq.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate
    FROM Users AS u
    WHERE
      u.Reputation > 10000
  ),
  QuestionWithMostPopularAnswer AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      a.Id AS AnswerId,
      a.OwnerUserId AS AnswerOwnerUserId,
      a.Score AS AnswerScore,
      a.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS answer_rank
    FROM Posts AS q
    JOIN Posts AS a
      ON q.Id = a.ParentId
    WHERE
      q.PostTypeId = 1 AND a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
  ),
  TopTierQuestions AS (
    SELECT
      q.QuestionId,
      q.QuestionTitle,
      q.AnswerId,
      q.AnswerScore,
      q.AnswerCreationDate,
      uqus.TotalRecentQuestions,
      uqus.TotalQuestionScore,
      uqus.AvgAnswersPerQuestion,
      hru.DisplayName AS OriginalPosterDisplayName,
      hru.Reputation AS OriginalPosterReputation,
      hru.UserCreationDate,
      CASE
        WHEN hru.UserCreationDate < (cast('2024-10-01' as date) - INTERVAL '5 years') THEN 'Veteran'
        WHEN hru.UserCreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '5 years') AND (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Established'
        ELSE 'New'
      END AS UserTenure
    FROM QuestionWithMostPopularAnswer AS q
    JOIN UserQuestionStats AS uqus
      ON q.AnswerOwnerUserId = uqus.OwnerUserId
    LEFT JOIN Users AS u
      ON q.AnswerOwnerUserId = u.Id
    LEFT JOIN HighReputationUsers AS hru
      ON q.QuestionId = hru.UserId
    WHERE
      q.answer_rank = 1 AND q.AnswerScore > 50 AND uqus.TotalRecentQuestions > 10
  )
SELECT
  q.QuestionTitle,
  q.AnswerScore AS BestAnswerScore,
  q.AnswerCreationDate,
  q.TotalRecentQuestions,
  q.TotalQuestionScore,
  q.AvgAnswersPerQuestion,
  q.OriginalPosterDisplayName,
  q.OriginalPosterReputation,
  q.UserTenure,
  COUNT(c.Id) AS NumberOfCommentsOnBestAnswer,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS NumberOfUpvotesOnBestAnswer,
  LOWER(SUBSTRING(COALESCE(p.Tags, 'no tags') FROM 2 FOR (POSITION('>' IN COALESCE(p.Tags, 'no tags')) - 2))) AS FirstTag,
  CASE
    WHEN q.TotalQuestionScore > 500 AND q.AvgAnswersPerQuestion > 5 THEN 'High Engagement'
    WHEN q.TotalQuestionScore < 50 THEN 'Low Engagement'
    ELSE 'Moderate Engagement'
  END AS EngagementLevel
FROM TopTierQuestions AS q
LEFT JOIN Comments AS c
  ON q.AnswerId = c.PostId
LEFT JOIN Votes AS v
  ON q.AnswerId = v.PostId AND v.VoteTypeId = 2
LEFT JOIN Posts AS p
  ON q.QuestionId = p.Id
WHERE
  q.OriginalPosterReputation IS NOT NULL OR q.UserTenure = 'Veteran'
GROUP BY
  q.QuestionTitle,
  q.AnswerScore,
  q.AnswerCreationDate,
  q.TotalRecentQuestions,
  q.TotalQuestionScore,
  q.AvgAnswersPerQuestion,
  q.OriginalPosterDisplayName,
  q.OriginalPosterReputation,
  q.UserTenure,
  LOWER(SUBSTRING(COALESCE(p.Tags, 'no tags') FROM 2 FOR (POSITION('>' IN COALESCE(p.Tags, 'no tags')) - 2)))
HAVING
  COUNT(c.Id) > 2
ORDER BY
  q.TotalQuestionScore DESC,
  q.AnswerScore DESC
LIMIT 10;