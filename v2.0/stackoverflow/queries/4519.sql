-- {"query": "4519.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1916}
WITH
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionSequenceForUser,
      AVG(CAST(p.AnswerCount AS DOUBLE PRECISION)) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate)) AS AvgAnswersPerMonth,
      SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViewsForUser,
      COUNT(a.Id) AS AnswerCountActual
    FROM Posts AS p
    LEFT JOIN Posts AS a
      ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT q.QuestionId) AS UserQuestionCount,
      SUM(CASE WHEN q.IsClosed = 1 THEN 1 ELSE 0 END) AS UserClosedQuestions,
      AVG(q.QuestionScore) AS AvgUserQuestionScore,
      MAX(q.QuestionCreationDate) AS LastQuestionDate,
      CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
      COUNT(b.Id) AS BadgeCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users AS u
    LEFT JOIN QuestionStats AS q
      ON u.Id = q.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes,
      u.WebsiteUrl
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCountPerPost,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
      AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AvgCommentScore,
      STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 50), ' | ') AS SampleComments
    FROM Comments AS c
    GROUP BY
      c.PostId
  ),
  PostHistorySummary AS (
    SELECT
      ph.PostId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEditCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEditCount,
      MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5)
    GROUP BY
      ph.PostId
  ),
  TopQuestionsWithDetails AS (
    SELECT
      qs.QuestionId,
      qs.Title,
      qs.QuestionScore,
      qs.QuestionViewCount,
      qs.AnswerCount,
      qs.FavoriteCount,
      ue.DisplayName AS OwnerDisplayName,
      ue.Reputation AS OwnerReputation,
      qs.IsClosed,
      qs.ClosedDate,
      ca.CommentCountPerPost,
      ca.AvgCommentScore,
      phs.LastEditDate,
      COALESCE(qs.AvgAnswersPerMonth, 0) AS MonthlyAvgAnswers,
      qs.CumulativeViewsForUser,
      qs.QuestionSequenceForUser,
      CASE
        WHEN qs.QuestionScore > 100 AND qs.AnswerCount > 10 AND qs.FavoriteCount > 5 THEN 'Highly Engaged'
        WHEN qs.QuestionScore > 50 THEN 'Popular'
        WHEN qs.AnswerCount > 5 THEN 'Well-Answered'
        ELSE 'Standard'
      END AS QuestionEngagementLevel,
      CASE
        WHEN qs.QuestionCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR) AND qs.IsClosed = 0 AND qs.AnswerCount = 0 THEN 'Stale and Unanswered'
        ELSE 'Active or Resolved'
      END AS QuestionAgeStatus,
      (qs.QuestionViewCount * 1.0 / NULLIF(qs.FavoriteCount, 0)) AS ViewsPerFavorite,
      LENGTH(qs.Title) AS TitleLength
    FROM QuestionStats AS qs
    JOIN UserEngagement AS ue
      ON qs.OwnerUserId = ue.UserId
    LEFT JOIN CommentAnalysis AS ca
      ON qs.QuestionId = ca.PostId
    LEFT JOIN PostHistorySummary AS phs
      ON qs.QuestionId = phs.PostId
    WHERE
      qs.QuestionScore > 0
      AND qs.QuestionViewCount > 100
      AND qs.QuestionCreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
  )
SELECT
  tqwd.QuestionId,
  tqwd.Title,
  tqwd.QuestionScore,
  tqwd.QuestionViewCount,
  tqwd.AnswerCount,
  tqwd.FavoriteCount,
  tqwd.OwnerDisplayName,
  tqwd.OwnerReputation,
  tqwd.IsClosed,
  tqwd.ClosedDate,
  tqwd.CommentCountPerPost,
  tqwd.AvgCommentScore,
  tqwd.LastEditDate,
  tqwd.MonthlyAvgAnswers,
  tqwd.CumulativeViewsForUser,
  tqwd.QuestionSequenceForUser,
  tqwd.QuestionEngagementLevel,
  tqwd.QuestionAgeStatus,
  tqwd.ViewsPerFavorite,
  tqwd.TitleLength,
  COALESCE(pl.RelatedPostId, -1) AS LinkedToPostId,
  COALESCE(lt.Name, 'Unknown') AS LinkType,
  CASE
    WHEN ue.Reputation > 100000 THEN 'Community Leader'
    WHEN ue.Reputation BETWEEN 50000 AND 100000 THEN 'Expert'
    WHEN ue.Reputation BETWEEN 10000 AND 50000 THEN 'Experienced'
    ELSE 'Novice'
  END AS UserExperienceLevel,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = tqwd.QuestionId AND v.VoteTypeId = 2
  ) AS UpvoteCountForQuestion,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = tqwd.QuestionId AND v.VoteTypeId = 3
  ) AS DownvoteCountForQuestion,
  CASE
    WHEN tqwd.OwnerDisplayName LIKE '%Moderator%' THEN 'Yes'
    ELSE 'No'
  END AS IsDisplayNameModerator,
  DENSE_RANK() OVER (PARTITION BY tqwd.QuestionEngagementLevel ORDER BY tqwd.QuestionScore DESC) AS RankWithinEngagementLevel
FROM TopQuestionsWithDetails AS tqwd
LEFT JOIN PostLinks AS pl
  ON tqwd.QuestionId = pl.PostId AND pl.LinkTypeId = 1
LEFT JOIN LinkTypes AS lt
  ON pl.LinkTypeId = lt.Id
LEFT JOIN UserEngagement AS ue
  ON tqwd.OwnerReputation = ue.Reputation AND tqwd.OwnerDisplayName = ue.DisplayName AND tqwd.OwnerReputation = ue.Reputation
WHERE
  tqwd.QuestionScore > 10
  AND tqwd.AnswerCount < 50
  AND tqwd.TitleLength BETWEEN 15 AND 150
  AND tqwd.OwnerReputation > 5000
  AND ue.GoldBadges > 0
ORDER BY
  tqwd.QuestionScore DESC,
  tqwd.QuestionViewCount DESC
LIMIT 100;