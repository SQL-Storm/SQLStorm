-- {"query": "4664.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1117} 

WITH
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      Score,
      AnswerCount,
      FavoriteCount,
      CreationDate
    FROM Posts
    WHERE
      PostTypeId = 1
      AND CreationDate >= DATE('now', '-1 year')
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT q.Id) AS QuestionsAsked,
      SUM(CASE WHEN q.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestions,
      COUNT(DISTINCT c.Id) AS CommentsMade,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments,
      COUNT(DISTINCT b.Id) AS BadgesEarned,
      MAX(b.Date) AS LastBadgeDate
    FROM Users AS u
    LEFT JOIN Posts AS q
      ON u.Id = q.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.Id <> -1
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  QuestionMetrics AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.Tags,
      q.Score,
      q.AnswerCount,
      q.FavoriteCount,
      q.CreationDate,
      ua.DisplayName AS OwnerDisplayName,
      ua.Reputation AS OwnerReputation,
      ua.QuestionsAsked,
      ua.CommentsMade,
      ua.BadgesEarned,
      RANK() OVER (ORDER BY q.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserQuestionOrder
    FROM RecentQuestions AS q
    LEFT JOIN UserActivity AS ua
      ON q.OwnerUserId = ua.UserId
  ),
  CommentDetails AS (
    SELECT
      c.Id,
      c.PostId,
      c.UserId,
      c.UserDisplayName,
      c.Score,
      c.Text,
      c.CreationDate,
      p.Title AS PostTitle,
      p.OwnerUserId AS PostOwnerUserId,
      CASE
        WHEN c.Score > 5 THEN 'Highly Valued'
        WHEN c.Score > 0 THEN 'Valued'
        ELSE 'Standard'
      END AS CommentValueCategory
    FROM Comments AS c
    JOIN Posts AS p
      ON c.PostId = p.Id
    WHERE
      c.CreationDate >= DATE('now', '-90 days')
  ),
  PostLinkAnalysis AS (
    SELECT
      pl.PostId,
      COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateLinks,
      COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedPosts,
      MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks AS pl
    GROUP BY
      pl.PostId
  )
SELECT
  qm.QuestionId,
  qm.Title,
  qm.OwnerDisplayName,
  qm.OwnerReputation,
  qm.QuestionsAsked,
  qm.Score,
  qm.ScoreRank,
  qm.AnswerCount,
  qm.FavoriteCount,
  qm.UserQuestionOrder,
  cd.CommentValueCategory,
  cd.Text AS SampleCommentText,
  COALESCE(pl.DuplicateLinks, 0) AS TotalDuplicateLinks,
  COALESCE(pl.LinkedPosts, 0) AS TotalLinkedPosts,
  IIF(qm.Score > 100 AND qm.AnswerCount > 10 AND qm.FavoriteCount > 5, 'Popular', IIF(qm.Score < 0 AND qm.AnswerCount = 0, 'Unpopular', 'Average')) AS PopularityStatus,
  CAST(strftime('%Y-%m-%d', qm.CreationDate) AS TEXT) AS QuestionDate
FROM QuestionMetrics AS qm
LEFT JOIN CommentDetails AS cd
  ON qm.QuestionId = cd.PostId AND cd.Score > 0
LEFT JOIN PostLinkAnalysis AS pl
  ON qm.QuestionId = pl.PostId
WHERE
  qm.OwnerReputation > 1000
  AND qm.Score > 0
  AND qm.UserQuestionOrder <= 5
  AND qm.Tags LIKE '%<sql>%'
  AND (
    cd.UserDisplayName IS NULL OR cd.UserDisplayName <> qm.OwnerDisplayName
  )
ORDER BY
  qm.Score DESC,
  qm.FavoriteCount DESC
LIMIT 100;
