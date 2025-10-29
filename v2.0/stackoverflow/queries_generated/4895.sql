-- {"query": "4895.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1589} 
WITH
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      p.ClosedDate,
      u.DisplayName AS OwnerDisplayName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF(day, p.CreationDate, p.ClosedDate)
        ELSE NULL
      END AS DaysToClose,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 -- Questions
      AND p.CreationDate >= '2023-01-01'
  ),
  AnswerStats AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS TotalAnswers,
      SUM(p.Score) AS TotalAnswerScore,
      AVG(p.Score) AS AvgAnswerScore,
      COUNT(CASE WHEN p.Id = pq.AcceptedAnswerId THEN 1 ELSE NULL END) AS IsAcceptedAnswerPresent,
      COUNT(CASE WHEN p.Score > 0 THEN 1 ELSE NULL END) AS AnswersWithPositiveScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS AnswerRank
    FROM Posts AS p
    LEFT JOIN Posts AS pq -- Alias for the question post
      ON p.ParentId = pq.Id
    WHERE
      p.PostTypeId = 2 -- Answers
    GROUP BY
      p.ParentId
  ),
  CommentStats AS (
    SELECT
      c.PostId AS QuestionId,
      COUNT(c.Id) AS TotalCommentsOnQuestion,
      SUM(c.Score) AS TotalCommentScore,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    JOIN Posts AS p
      ON c.PostId = p.Id
    WHERE
      p.PostTypeId = 1
    GROUP BY
      c.PostId
  ),
  UserReputation AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      CreationDate,
      Views,
      UpVotes AS UserUpVotes,
      DownVotes AS UserDownVotes,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS RepRank
    FROM Users
  ),
  TopTagQuestions AS (
    SELECT
      qs.QuestionId,
      qs.Title,
      qs.OwnerUserId,
      qs.QuestionScore,
      qs.AnswerCount,
      qs.QuestionCreationDate,
      qs.OwnerDisplayName,
      TRIM(BOTH '''' FROM UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(qs.Tags, '<', ''), '>', ''), ' '))) AS Tag,
      ROW_NUMBER() OVER (PARTITION BY TRIM(BOTH '''' FROM UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(qs.Tags, '<', ''), '>', ''), ' '))) ORDER BY qs.QuestionScore DESC) AS TagQuestionRank
    FROM QuestionStats AS qs
    WHERE
      qs.Tags IS NOT NULL
      AND qs.Tags != ''
  ),
  AllTags AS (
    SELECT DISTINCT
      TRIM(BOTH '''' FROM UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(Tags, '<', ''), '>', ''), ' '))) AS TagName
    FROM Posts
    WHERE
      PostTypeId = 1
  )
SELECT
  qs.QuestionId,
  qs.Title,
  qs.OwnerDisplayName AS QuestionOwner,
  qs.QuestionCreationDate,
  qs.QuestionScore,
  qs.AnswerCount,
  qs.QuestionViewCount,
  qs.FavoriteCount,
  COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
  COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
  ans.AvgAnswerScore,
  COALESCE(ans.IsAcceptedAnswerPresent, 0) AS AcceptedAnswerExists,
  COALESCE(ans.AnswersWithPositiveScore, 0) AS AnswersWithPositiveScore,
  COALESCE(com.TotalCommentsOnQuestion, 0) AS TotalCommentsOnQuestion,
  COALESCE(com.TotalCommentScore, 0) AS TotalCommentScore,
  com.AvgCommentScore,
  qs.DaysToClose,
  qs.ClosedDate,
  ur.Reputation AS OwnerReputation,
  ur.UserUpVotes AS OwnerTotalUpVotes,
  ur.UserDownVotes AS OwnerTotalDownVotes,
  ur.RepRank AS OwnerReputationRank,
  ttq.Tag AS TopTagForThisQuestion,
  ttq.TagQuestionRank AS RankOfThisQuestionInItsTopTag,
  CASE
    WHEN qs.QuestionScore > 100 AND qs.AnswerCount > 10 AND qs.FavoriteCount > 5 THEN 'High Engagement'
    WHEN qs.QuestionScore > 50 AND qs.AnswerCount > 5 THEN 'Moderate Engagement'
    ELSE 'Low Engagement'
  END AS EngagementLevel,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = qs.QuestionId
      AND pl.LinkTypeId = 3 -- Duplicate
  ) AS NumberOfDuplicateLinks,
  SUBSTRING(qs.Title FROM 1 FOR 10) AS FirstTenCharsOfTitle,
  CASE
    WHEN qs.OwnerUserId = -1 THEN 'Community Wiki'
    ELSE 'User Contributed'
  END AS OwnerType,
  at.TagName AS AnotherTagFromAllTags,
  ROW_NUMBER() OVER (ORDER BY qs.QuestionScore DESC, qs.AnswerCount DESC) AS OverallQuestionRank
FROM QuestionStats AS qs
LEFT JOIN AnswerStats AS ans
  ON qs.QuestionId = ans.QuestionId
LEFT JOIN CommentStats AS com
  ON qs.QuestionId = com.QuestionId
LEFT JOIN UserReputation AS ur
  ON qs.OwnerUserId = ur.UserId
LEFT JOIN TopTagQuestions AS ttq
  ON qs.QuestionId = ttq.QuestionId AND ttq.TagQuestionRank = 1
LEFT JOIN AllTags AS at
  ON CAST(RANDOM() * 10000 AS INT) % (SELECT COUNT(*) FROM AllTags) + 1 = at.Id -- Randomly join a tag for variety
WHERE
  qs.RowNum <= 1000 -- Limit to top 1000 recent questions for performance
  AND qs.QuestionScore > 0
  AND (
    qs.ClosedDate IS NULL OR qs.ClosedDate > qs.CreationDate
  )
ORDER BY
  qs.QuestionCreationDate DESC
LIMIT 100;