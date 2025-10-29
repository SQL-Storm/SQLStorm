-- {"query": "1239.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1838} 
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS TotalUpVotes,
        u.DownVotes AS TotalDownVotes,
        u.Views AS ProfileViews,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        DATE_PART('day', u.LastAccessDate - u.CreationDate) AS DaysSinceCreation,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        MAX(b.Date) AS LatestBadgeDate,
        AVG(CASE WHEN b.TagBased = TRUE THEN 1.0 ELSE 0.0 END) AS AvgTagBasedBadgesRatio,
        COALESCE(u.Location, 'Unknown') AS UserLocation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation >= 1000
      AND u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate, u.LastAccessDate, u.Location
    HAVING COUNT(DISTINCT b.Id) >= 5
),
PostLifecycleEvents AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastEditDateHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDateHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenedDateHistory,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS FirstClosedDateHistory,
        ARRAY_AGG(DISTINCT ph.PostHistoryTypeId ORDER BY ph.PostHistoryTypeId) AS AllHistoryTypes,
        AVG(CASE WHEN ph.UserId IS NOT NULL THEN (SELECT u2.Reputation FROM Users u2 WHERE u2.Id = ph.UserId) ELSE 0 END) AS AvgEditorReputation
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId NOT IN (1, 2, 3)
    GROUP BY ph.PostId
),
QuestionDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.LastActivityDate,
        q.LastEditDate,
        COALESCE(q.OwnerDisplayName, 'Community') AS QuestionOwnerDisplayName,
        STRING_TO_ARRAY(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><') AS TagArray,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(DISTINCT a.Id) AS EffectiveAnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Score END) AS AcceptedAnswerScore,
        MIN(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.CreationDate END) AS AcceptedAnswerDate,
        DATE_PART('day', MIN(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.CreationDate END) - q.CreationDate) AS DaysToAcceptedAnswer,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = q.Id AND c.Score >= 5) AS HighScoreCommentsOnQuestion,
        RANK() OVER (PARTITION BY q.OwnerUserId ORDER BY q.ViewCount DESC) AS RankByViewCountForUser,
        NTILE(4) OVER (ORDER BY q.Score DESC) AS ScoreQuartile
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year'
    GROUP BY q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.FavoriteCount, q.ClosedDate, q.LastActivityDate, q.LastEditDate, q.OwnerDisplayName, q.Tags
    HAVING COUNT(a.Id) > 0
)
SELECT
    ue.DisplayName AS UserDisplayName,
    ue.Reputation,
    ue.ProfileViews,
    ue.UserLocation,
    ue.GoldBadges,
    qd.QuestionId,
    qd.Title AS QuestionTitle,
    qd.QuestionCreationDate,
    qd.QuestionScore,
    qd.ViewCount AS QuestionViewCount,
    qd.FavoriteCount,
    qd.TotalAnswerScore,
    qd.AvgAnswerScore,
    qd.AcceptedAnswerScore,
    qd.DaysToAcceptedAnswer,
    qd.HighScoreCommentsOnQuestion,
    ple.TotalHistoryEvents,
    ple.DistinctEditors,
    COALESCE(ple.LastClosedDateHistory, qd.ClosedDate) AS ActualClosedDate,
    DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - qd.QuestionCreationDate) AS QuestionAgeDays,
    NULLIF(qd.QuestionScore, 0) / NULLIF(qd.ViewCount, 0) AS ScorePerViewRatio,
    CASE
        WHEN qd.ClosedDate IS NOT NULL AND ple.LastReopenedDateHistory IS NULL THEN 'Closed'
        WHEN qd.ClosedDate IS NOT NULL AND ple.LastReopenedDateHistory IS NOT NULL AND ple.LastReopenedDateHistory > COALESCE(ple.LastClosedDateHistory, qd.ClosedDate) THEN 'Reopened'
        WHEN qd.ClosedDate IS NULL THEN 'Open'
        ELSE 'Ambiguous'
    END AS QuestionStatus,
    (SELECT COUNT(DISTINCT t.Id) FROM Tags t WHERE t.TagName IN (SELECT UNNEST(qd.TagArray))) AS UniqueTagsMatched,
    MIN(qd.QuestionCreationDate) OVER (PARTITION BY ue.UserLocation) AS EarliestQuestionInLocation,
    AVG(qd.QuestionScore) OVER (PARTITION BY ue.UserLocation) AS AvgQuestionScoreInLocation,
    FIRST_VALUE(qd.Title) OVER (PARTITION BY ue.UserLocation ORDER BY qd.ViewCount DESC) AS MostViewedQuestionInLocation,
    CASE
        WHEN ue.Reputation > 10000 AND ue.GoldBadges >= 3 THEN 'High-Achiever'
        WHEN ue.Reputation > 5000 AND ue.GoldBadges >= 1 THEN 'Mid-Achiever'
        ELSE 'Regular'
    END AS UserAchievementLevel,
    SUM(CASE WHEN qd.ScoreQuartile = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY ue.UserId) AS TopQuartileQuestionsByThisUser
FROM UserEngagement ue
JOIN QuestionDetails qd ON ue.UserId = qd.OwnerUserId
LEFT JOIN PostLifecycleEvents ple ON qd.QuestionId = ple.PostId
WHERE qd.QuestionScore > 10
  AND qd.ViewCount > 500
  AND qd.FavoriteCount > 0
  AND ple.TotalHistoryEvents IS NOT NULL
  AND (qd.Title LIKE '%SQL%' OR qd.Title LIKE '%database%')
  AND (qd.DaysToAcceptedAnswer IS NULL OR qd.DaysToAcceptedAnswer <= 30)
ORDER BY ue.Reputation DESC, qd.QuestionScore DESC, qd.QuestionCreationDate DESC
LIMIT 500;