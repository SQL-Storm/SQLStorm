-- {"query": "4764.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1820}
WITH
  PostQuestion AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      CreationDate,
      Score,
      AnswerCount,
      FavoriteCount,
      CASE
        WHEN ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed
    FROM Posts
    WHERE
      PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(pq.Id) AS QuestionsPosted,
      SUM(pq.Score) AS TotalQuestionScore,
      AVG(pq.AnswerCount) AS AvgAnswersPerQuestion,
      COUNT(DISTINCT b.Id) AS TotalBadges,
      MAX(pq.CreationDate) AS LatestQuestionDate,
      COUNT(CASE WHEN pq.IsClosed = 1 THEN pq.Id ELSE NULL END) AS ClosedQuestions
    FROM Users AS u
    LEFT JOIN PostQuestion AS pq
      ON u.Id = pq.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  TagEngagement AS (
    SELECT
      t.TagName,
      SUM(CASE WHEN pq.OwnerUserId = t.Id THEN 1 ELSE 0 END) AS QuestionsWithTag,
      AVG(pq.Score) AS AvgScoreForTag,
      SUM(pq.FavoriteCount) AS TotalFavoritesForTag,
      COUNT(DISTINCT COALESCE(pq.OwnerUserId, -1)) AS DistinctTagOwners
    FROM Tags AS t
    LEFT JOIN PostQuestion AS pq
      ON pq.Tags LIKE '%' || t.TagName || '%'
    GROUP BY
      t.TagName
  ),
  ComplexCalculations AS (
    SELECT
      pq.Id AS QuestionId,
      ua.DisplayName AS OwnerDisplayName,
      pq.Title,
      pq.Tags,
      pq.CreationDate AS QuestionCreationDate,
      pq.Score AS QuestionScore,
      pq.AnswerCount AS QuestionAnswerCount,
      pq.FavoriteCount AS QuestionFavoriteCount,
      ua.Reputation AS OwnerReputation,
      ua.UserCreationDate,
      ua.QuestionsPosted AS OwnerTotalQuestions,
      ua.TotalQuestionScore AS OwnerTotalQuestionScore,
      ua.AvgAnswersPerQuestion AS OwnerAvgAnswers,
      ua.TotalBadges AS OwnerTotalBadges,
      ua.ClosedQuestions AS OwnerClosedQuestions,
      DENSE_RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank,
      ROW_NUMBER() OVER (PARTITION BY pq.OwnerUserId ORDER BY pq.CreationDate DESC) AS UserQuestionSequence,
      CASE
        WHEN pq.FavoriteCount > (ua.QuestionsPosted / 2.0) THEN 'High Engagement'
        WHEN pq.Score > 50 AND pq.AnswerCount > 10 THEN 'Popular'
        ELSE 'Standard'
      END AS QuestionCategorization,
      ua.LatestQuestionDate,
      ua.UserCreationDate + INTERVAL '30 days' AS ThirtyDaysAfterUserCreation,
      ua.DisplayName || ' (' || ua.Reputation || ' Rep)' AS DisplayNameWithReputation,
      (
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - pq.CreationDate)) / 86400.0
      ) AS DaysSinceCreation,
      LAG(pq.Score, 1, 0) OVER (ORDER BY pq.CreationDate) AS PreviousQuestionScore,
      LEAD(pq.Score, 1, 0) OVER (ORDER BY pq.CreationDate) AS NextQuestionScore,
      CASE
        WHEN pq.OwnerUserId IS NULL THEN 'Community'
        WHEN pq.Score > 0 THEN 'Accepted'
        ELSE 'Pending'
      END AS Status,
      SUBSTRING(pq.Tags FROM 2 FOR (CHAR_LENGTH(pq.Tags) - 2)) AS CleanTags,
      CASE
        WHEN pq.OwnerUserId IS NOT NULL AND ua.UserCreationDate < pq.CreationDate THEN 1
        ELSE 0
      END AS OwnerExistsBeforeQuestion,
      pq.IsClosed,
      pq.FavoriteCount
    FROM PostQuestion AS pq
    JOIN UserActivity AS ua
      ON pq.OwnerUserId = ua.UserId
  )
SELECT
  cc.QuestionId,
  cc.Title,
  cc.Tags,
  cc.QuestionCreationDate,
  cc.QuestionScore,
  cc.QuestionAnswerCount,
  cc.QuestionFavoriteCount,
  cc.OwnerDisplayName,
  cc.OwnerReputation,
  cc.UserCreationDate,
  cc.OwnerTotalQuestions,
  cc.OwnerTotalQuestionScore,
  cc.OwnerAvgAnswers,
  cc.OwnerTotalBadges,
  cc.OwnerClosedQuestions,
  cc.ReputationRank,
  cc.UserQuestionSequence,
  cc.QuestionCategorization,
  cc.LatestQuestionDate,
  cc.ThirtyDaysAfterUserCreation,
  cc.DisplayNameWithReputation,
  cc.DaysSinceCreation,
  cc.PreviousQuestionScore,
  cc.NextQuestionScore,
  cc.Status,
  cc.CleanTags,
  cc.OwnerExistsBeforeQuestion,
  te.TagName,
  te.QuestionsWithTag,
  te.AvgScoreForTag,
  te.TotalFavoritesForTag,
  te.DistinctTagOwners,
  CASE
    WHEN cc.OwnerReputation > 10000 AND cc.QuestionScore > 50 THEN 'High Impact User'
    WHEN cc.DaysSinceCreation > 365 AND cc.OwnerTotalBadges > 5 THEN 'Experienced User'
    WHEN cc.OwnerClosedQuestions > 5 THEN 'Frequent Closer'
    ELSE 'Regular User'
  END AS UserImpactLevel,
  cc.IsClosed
FROM ComplexCalculations AS cc
LEFT JOIN PostLinks AS pl
  ON cc.QuestionId = pl.PostId
LEFT JOIN TagEngagement AS te
  ON cc.Tags LIKE '%' || te.TagName || '%'
WHERE
  cc.QuestionScore > -5
  AND cc.OwnerReputation >= 0
  AND cc.DaysSinceCreation BETWEEN 1 AND 1000
  AND cc.OwnerDisplayName IS NOT NULL
  AND cc.OwnerDisplayName <> ''
  AND (
    cc.QuestionCategorization = 'Popular'
    OR cc.OwnerTotalBadges > 10
  )
  AND cc.UserQuestionSequence <= 5
UNION ALL
SELECT
  cc.QuestionId,
  cc.Title,
  cc.Tags,
  cc.QuestionCreationDate,
  cc.QuestionScore,
  cc.QuestionAnswerCount,
  cc.QuestionFavoriteCount,
  cc.OwnerDisplayName,
  cc.OwnerReputation,
  cc.UserCreationDate,
  cc.OwnerTotalQuestions,
  cc.OwnerTotalQuestionScore,
  cc.OwnerAvgAnswers,
  cc.OwnerTotalBadges,
  cc.OwnerClosedQuestions,
  cc.ReputationRank,
  cc.UserQuestionSequence,
  cc.QuestionCategorization,
  cc.LatestQuestionDate,
  cc.ThirtyDaysAfterUserCreation,
  cc.DisplayNameWithReputation,
  cc.DaysSinceCreation,
  cc.PreviousQuestionScore,
  cc.NextQuestionScore,
  cc.Status,
  cc.CleanTags,
  cc.OwnerExistsBeforeQuestion,
  NULL AS TagName,
  NULL AS QuestionsWithTag,
  NULL AS AvgScoreForTag,
  NULL AS TotalFavoritesForTag,
  NULL AS DistinctTagOwners,
  'Featured' AS UserImpactLevel,
  cc.IsClosed
FROM ComplexCalculations AS cc
WHERE
  cc.QuestionFavoriteCount > 100
  AND cc.QuestionScore > 200
  AND cc.OwnerReputation > 50000
;