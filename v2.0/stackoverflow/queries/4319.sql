WITH
  LatestEdits AS (
    SELECT
      ph.PostId,
      ph.UserId AS EditorUserId,
      u.DisplayName AS EditorDisplayName,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Users u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 7, 8)
  ),
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS QuestionCreationDate,
      p.OwnerUserId AS QuestionOwnerUserId,
      u.DisplayName AS QuestionOwnerDisplayName,
      COALESCE(le.EditDate, p.LastEditDate) AS LastEditDate,
      COALESCE(le.EditorUserId, p.LastEditorUserId) AS LastEditorUserId,
      COALESCE(le.EditorDisplayName, p.LastEditorDisplayName) AS LastEditorDisplayName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END AS QuestionStatus
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN LatestEdits le
      ON p.Id = le.PostId
      AND le.rn = 1
    WHERE
      pt.Name = 'Question'
    GROUP BY
      p.Id,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.OwnerUserId,
      u.DisplayName,
      p.LastEditDate,
      p.LastEditorUserId,
      p.LastEditorDisplayName,
      p.ClosedDate,
      p.CommunityOwnedDate,
      le.EditDate,
      le.EditorUserId,
      le.EditorDisplayName
  ),
  AnswerDetails AS (
    SELECT
      pa.ParentId AS QuestionId,
      COUNT(pa.Id) AS AnswerCount,
      SUM(pa.Score) AS TotalAnswerScore,
      AVG(pa.Score) AS AverageAnswerScore,
      MAX(pa.CreationDate) AS LatestAnswerDate,
      SUM(CASE WHEN pa.Id = p_q.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts pa
    LEFT JOIN Posts p_q
      ON pa.ParentId = p_q.Id
    WHERE
      pa.PostTypeId = 2
    GROUP BY
      pa.ParentId
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionsAsked,
      COUNT(CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswersGiven,
      COUNT(DISTINCT b.Id) AS BadgesEarned,
      SUM(CASE WHEN pt.Name = 'Question' THEN p.Score ELSE 0 END) AS TotalQuestionScore,
      SUM(CASE WHEN pt.Name = 'Answer' THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      MAX(p.CreationDate) AS LastPostDate,
      AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      t.Count AS TagCount,
      (
        SELECT
          COUNT(DISTINCT p.OwnerUserId)
        FROM Posts p
        WHERE
          p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%'
      ) AS DistinctQuestionAuthors,
      (
        SELECT
          AVG(p.Score)
        FROM Posts p
        WHERE
          p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%'
      ) AS AverageQuestionScoreForTag,
      (
        SELECT
          COUNT(p.Id)
        FROM Posts p
        WHERE
          p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%'
      ) AS TotalQuestionsWithTag
    FROM Tags t
    ORDER BY
      t.Count DESC
    LIMIT 100
  ),
  MainQuery AS (
    SELECT
      qs.Title,
      qs.QuestionScore,
      qs.AnswerCount AS QuestionAnswerCount,
      COALESCE(ad.AnswerCount, 0) AS TotalAnswers,
      COALESCE(ad.TotalAnswerScore, 0) AS TotalScoreOfAnswers,
      ad.AverageAnswerScore,
      qs.FavoriteCount,
      qs.QuestionStatus,
      qs.QuestionOwnerDisplayName,
      qs.LastEditorDisplayName AS LatestEditor,
      qs.LastEditDate AS LatestEditTimestamp,
      uc.DisplayName AS TopContributor,
      uc.QuestionsAsked,
      uc.AnswersGiven,
      uc.BadgesEarned,
      uc.AvgPostScore AS UserAveragePostScore,
      tp.TagName AS MostPopularTag,
      tp.TagCount AS TagPopularityCount,
      tp.AverageQuestionScoreForTag AS AvgQuestionScoreForPopularTag,
      CASE
        WHEN qs.QuestionScore > 100 AND qs.AnswerCount > 5 THEN 'High Engagement'
        WHEN qs.QuestionScore < 0 THEN 'Negative Score'
        WHEN qs.AnswerCount = 0 AND qs.QuestionScore > 0 THEN 'Unanswered, Positive Score'
        ELSE 'Standard'
      END AS QuestionEngagementCategory,
      (
        SELECT
          SUM(c.Score)
        FROM Comments c
        WHERE
          c.PostId = qs.QuestionId
      ) AS TotalCommentsScoreOnQuestion,
      qs.QuestionId,
      qs.QuestionCreationDate,
      qs.LastEditorUserId
    FROM QuestionStats qs
    LEFT JOIN AnswerDetails ad
      ON qs.QuestionId = ad.QuestionId
    LEFT JOIN UserContribution uc
      ON qs.QuestionOwnerUserId = uc.UserId
    LEFT JOIN TagPopularity tp
      ON qs.Title LIKE '%' || tp.TagName || '%' -- Simple heuristic to associate tags with questions
    WHERE
      qs.QuestionScore > 0
      AND qs.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
      AND EXISTS (
        SELECT
          1
        FROM PostLinks pl
        WHERE
          pl.PostId = qs.QuestionId AND pl.LinkTypeId = 3
      )
  ),
  UsersHighRep AS (
    SELECT
      NULL::varchar AS Title,
      NULL::integer AS QuestionScore,
      NULL::integer AS QuestionAnswerCount,
      NULL::integer AS TotalAnswers,
      NULL::integer AS TotalScoreOfAnswers,
      NULL::numeric AS AverageAnswerScore,
      NULL::integer AS FavoriteCount,
      NULL::varchar AS QuestionStatus,
      NULL::varchar AS QuestionOwnerDisplayName,
      NULL::varchar AS LatestEditor,
      NULL::timestamp AS LatestEditTimestamp,
      u.DisplayName AS TopContributor,
      NULL::integer AS QuestionsAsked,
      NULL::integer AS AnswersGiven,
      NULL::integer AS BadgesEarned,
      NULL::numeric AS UserAveragePostScore,
      NULL::varchar AS MostPopularTag,
      NULL::integer AS TagPopularityCount,
      NULL::numeric AS AvgQuestionScoreForPopularTag,
      NULL::varchar AS QuestionEngagementCategory,
      NULL::integer AS TotalCommentsScoreOnQuestion,
      NULL::integer AS QuestionId,
      NULL::timestamp AS QuestionCreationDate,
      NULL::integer AS LastEditorUserId
    FROM Users u
    WHERE
      u.Reputation > 50000
      AND u.DownVotes = 0
  )
SELECT *
FROM (
  SELECT * FROM MainQuery
  UNION ALL
  SELECT * FROM UsersHighRep
) combined
ORDER BY RANDOM()
LIMIT 100;