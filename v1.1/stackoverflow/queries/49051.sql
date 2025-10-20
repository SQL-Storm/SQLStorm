WITH TargetTags AS (
    SELECT 'sql-server' AS Tag
    UNION ALL SELECT 'database-performance'
    UNION ALL SELECT 'optimization'
    UNION ALL SELECT 'postgresql'
    UNION ALL SELECT 'mysql'
    UNION ALL SELECT 'indexing'
),
UserQuestionPostHistory AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(ph.Id) AS QuestionEditCount,
        MAX(ph.CreationDate) AS LastQuestionEditDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND p.OwnerUserId = ph.UserId
    WHERE p.PostTypeId = 1
      AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY p.OwnerUserId
),
UserAnswerCommentActivity AS (
    SELECT
        q.OwnerUserId AS UserId,
        COUNT(c.Id) AS AnswerCommentCount,
        COUNT(DISTINCT c.PostId) AS DistinctAnswerCommented,
        MAX(c.CreationDate) AS LastAnswerCommentDate
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    JOIN Comments c ON a.Id = c.PostId AND q.OwnerUserId = c.UserId
    WHERE q.PostTypeId = 1
      AND a.PostTypeId = 2
    GROUP BY q.OwnerUserId
),
RelevantQuestionsWithTags AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Title,
        ARRAY_AGG(tt.Tag) FILTER (WHERE tt.Tag IS NOT NULL) AS MatchedTags
    FROM Posts q
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2), '><')) AS q_tag(tag) ON TRUE
    LEFT JOIN TargetTags tt ON q_tag.tag = tt.Tag
    WHERE q.PostTypeId = 1
      AND q.Tags IS NOT NULL
      AND tt.Tag IS NOT NULL
    GROUP BY q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Title
    HAVING COUNT(tt.Tag) > 0
),
HighScoringAnswersToRelevantQuestions AS (
    SELECT
        r.OwnerUserId AS QuestionOwnerId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        r.QuestionId,
        r.QuestionCreationDate
    FROM Posts a
    JOIN RelevantQuestionsWithTags r ON a.ParentId = r.QuestionId
    WHERE a.PostTypeId = 2
      AND a.Score >= 10
),
UserQuestionPerformance AS (
    SELECT
        hs.QuestionOwnerId AS UserId,
        COUNT(DISTINCT hs.QuestionId) AS TotalQuestionsAsked,
        COUNT(hs.AnswerId) AS TotalHighScoringAnswers,
        SUM(hs.AnswerScore) AS SumOfHighScoringAnswerScores,
        AVG(hs.AnswerScore) AS AvgHighScoringAnswerScore,
        MAX(hs.AnswerScore) AS MaxHighScoringAnswerScore,
        AVG(EXTRACT(EPOCH FROM (hs.AnswerCreationDate - hs.QuestionCreationDate))/(3600*24)) AS AvgTimeToAnswerDays
    FROM HighScoringAnswersToRelevantQuestions hs
    GROUP BY hs.QuestionOwnerId
),
UserReputationAndBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgesCount,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate, u.UpVotes, u.DownVotes, u.Views
)
SELECT
    uos.UserId,
    uos.DisplayName,
    uos.Reputation,
    uos.UpVotes,
    uos.Views,
    COALESCE(uqp.TotalQuestionsAsked, 0) AS TotalQuestionsAsked,
    COALESCE(uqp.TotalHighScoringAnswers, 0) AS TotalHighScoringAnswers,
    COALESCE(uqp.SumOfHighScoringAnswerScores, 0) AS SumOfHighScoringAnswerScores,
    COALESCE(uqp.AvgHighScoringAnswerScore, 0) AS AvgHighScoringAnswerScore,
    COALESCE(uqp.MaxHighScoringAnswerScore, 0) AS MaxHighScoringAnswerScore,
    COALESCE(uqp.AvgTimeToAnswerDays, 0) AS AvgTimeToAnswerDays,
    COALESCE(uqph.QuestionEditCount, 0) AS SelfEditCount,
    COALESCE(uaca.AnswerCommentCount, 0) AS SelfCommentOnAnswerCount,
    COALESCE(uaca.DistinctAnswerCommented, 0) AS DistinctAnswerCommented,
    uos.TotalBadges,
    uos.GoldBadgesCount,
    uos.LastBadgeDate,
    EXTRACT(YEAR FROM AGE(CAST('2024-10-01 12:34:56' AS TIMESTAMP), uos.UserCreationDate)) AS YearsOnPlatform,
    (
        (COALESCE(uqp.TotalHighScoringAnswers,0) * 15.0) +
        (COALESCE(uqp.SumOfHighScoringAnswerScores,0) * 0.7) +
        (COALESCE(uqph.QuestionEditCount,0) * 5.0) +
        (COALESCE(uaca.AnswerCommentCount,0) * 3.0) +
        (uos.GoldBadgesCount * 50.0) +
        (uos.Reputation * 0.01) +
        (uos.Views * 0.005)
    ) AS EngagementImpactScore,
    RANK() OVER (ORDER BY (
        (COALESCE(uqp.TotalHighScoringAnswers,0) * 15.0) +
        (COALESCE(uqp.SumOfHighScoringAnswerScores,0) * 0.7) +
        (COALESCE(uqph.QuestionEditCount,0) * 5.0) +
        (COALESCE(uaca.AnswerCommentCount,0) * 3.0) +
        (uos.GoldBadgesCount * 50.0) +
        (uos.Reputation * 0.01) +
        (uos.Views * 0.005)
    ) DESC) AS OverallEngagementRank,
    NTILE(5) OVER (ORDER BY COALESCE(uqp.AvgTimeToAnswerDays, 0) ASC) AS SpeedyAnswererQuintile
FROM UserReputationAndBadgeStats uos
LEFT JOIN UserQuestionPerformance uqp ON uos.UserId = uqp.UserId
LEFT JOIN UserQuestionPostHistory uqph ON uos.UserId = uqph.UserId
LEFT JOIN UserAnswerCommentActivity uaca ON uos.UserId = uaca.UserId
WHERE
    uos.Reputation > 5000
    AND COALESCE(uqp.TotalQuestionsAsked, 0) > 10
    AND COALESCE(uqp.TotalHighScoringAnswers, 0) > 5
    AND COALESCE(uqph.QuestionEditCount, 0) > 2
    AND uos.UserCreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
ORDER BY EngagementImpactScore DESC, OverallEngagementRank
LIMIT 50;