-- {"query": "1943.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2827}
WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        AVG(CAST(p.Score AS NUMERIC)) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
PostQualityMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        COALESCE(SUM(a.Score), 0) AS TotalAnswerScore,
        COALESCE(AVG(CAST(a.Score AS NUMERIC)), 0) AS AvgAnswerScore,
        COUNT(DISTINCT co.Id) AS QuestionCommentCount,
        CASE
            WHEN SUM(a.Score) > 0 AND q.AcceptedAnswerId IS NOT NULL THEN
                COALESCE(MAX(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Score ELSE 0 END), 0) * 1.0 / SUM(a.Score)
            ELSE 0
        END AS AcceptedAnswerScoreRatio,
        COALESCE(q.Score * 1.0 / NULLIF(q.ViewCount, 0), 0) AS ScorePerView,
        (q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<database>%' OR q.Tags LIKE '%<performance>%') AS HasComplexTags
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Comments co ON q.Id = co.PostId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.AcceptedAnswerId, q.Tags
),
UserBadgeProgression AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) AS BadgeSequence,
        DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Class, b.Date) AS RankWithinClass,
        LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS PreviousBadgeDate,
        COALESCE(EXTRACT(EPOCH FROM (b.Date - LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date))) / 86400, 0) AS DaysSincePrevBadge,
        u.Reputation * 1.0 / NULLIF(EXTRACT(EPOCH FROM (b.Date - u.CreationDate)) / 86400, 0) AS RepPerDayAtBadgeDate
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE b.Class IN (1, 2)
),
ContentEditorStats AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        COUNT(ph.Id) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        p.OwnerUserId,
        MAX(CASE WHEN ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnerEdited,
        MAX(CASE WHEN ph.UserId IS NOT NULL AND ph.UserId != p.OwnerUserId THEN 1 ELSE 0 END) AS OtherUserEdited,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    GROUP BY ph.PostId, ph.UserId, p.OwnerUserId
),
SelfCommentedAcceptedAnswers AS (
    SELECT DISTINCT
        p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND EXISTS (
          SELECT 1
          FROM Comments c
          WHERE c.PostId = p.Id
            AND c.UserId = p.OwnerUserId
      )
),
AggregatedQuestionMetrics AS (
    SELECT
        OwnerUserId AS UserId,
        SUM(QuestionScore) AS TotalOwnedQuestionScore,
        AVG(AvgAnswerScore) AS AvgAnswerScoreForOwnedQuestions,
        SUM(CASE WHEN HasComplexTags THEN 1 ELSE 0 END) AS ComplexTagQuestionCount
    FROM PostQualityMetrics
    GROUP BY OwnerUserId
),
AggregatedEditorMetrics AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(DISTINCT PostId) AS PostsEditedByOthersCount
    FROM ContentEditorStats
    WHERE OtherUserEdited = 1
    GROUP BY OwnerUserId
),
ProblematicPostSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS ProblematicPostsCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND (
          (p.Score < 0 AND p.CommentCount > 5)
          OR
          EXISTS (
              SELECT 1
              FROM PostHistory ph
              WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
              GROUP BY ph.PostId
              HAVING COUNT(ph.Id) >= 3
          )
      )
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    us.TotalPosts,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalPostScore,
    us.AvgPostScore,
    us.TotalCommentsMade,
    bprog.BadgeName AS LatestGoldSilverBadge,
    bprog.BadgeDate AS LatestBadgeDate,
    bprog.DaysSincePrevBadge AS DaysBetweenLastTwoBadges,
    bprog.RepPerDayAtBadgeDate,
    aqm.TotalOwnedQuestionScore,
    aqm.AvgAnswerScoreForOwnedQuestions,
    aqm.ComplexTagQuestionCount,
    aem.PostsEditedByOthersCount,
    RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS RepRankInLocation,
    CASE WHEN scaa.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS HasSelfCommentedAcceptedAnswer,
    (
        (u.Reputation * 0.1) +
        (COALESCE(us.TotalPostScore, 0) * 0.05) +
        (COALESCE(us.AvgPostScore, 0) * 10) +
        (COALESCE(bprog.BadgeSequence, 0) * 5) +
        (COALESCE(aqm.AvgAnswerScoreForOwnedQuestions, 0) * 2) +
        (CASE WHEN scaa.UserId IS NOT NULL THEN 50 ELSE 0 END) -
        (COALESCE(pps.ProblematicPostsCount, 0) * 10)
    ) AS InfluenceScore,
    u.DisplayName || ' - ' || COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 50), '') || (CASE WHEN LENGTH(COALESCE(u.AboutMe, '')) > 50 THEN '...' ELSE '' END) AS UserBioSnippet,
    COALESCE(pps.ProblematicPostsCount, 0) AS ProblematicPostsCount
FROM Users u
LEFT JOIN UserPostStats us ON u.Id = us.UserId
LEFT JOIN (
    SELECT UserId, BadgeName, BadgeDate, DaysSincePrevBadge, RepPerDayAtBadgeDate, BadgeSequence
    FROM UserBadgeProgression UBP_Gold
    WHERE RankWithinClass = 1 AND BadgeClass = 1
    UNION ALL
    SELECT UserId, BadgeName, BadgeDate, DaysSincePrevBadge, RepPerDayAtBadgeDate, BadgeSequence
    FROM UserBadgeProgression UBP_Silver
    WHERE RankWithinClass = 1 AND BadgeClass = 2 AND NOT EXISTS (SELECT 1 FROM UserBadgeProgression WHERE UserId = UBP_Silver.UserId AND BadgeClass = 1)
) AS bprog ON u.Id = bprog.UserId
LEFT JOIN AggregatedQuestionMetrics aqm ON u.Id = aqm.UserId
LEFT JOIN AggregatedEditorMetrics aem ON u.Id = aem.UserId
LEFT JOIN SelfCommentedAcceptedAnswers scaa ON u.Id = scaa.UserId
LEFT JOIN ProblematicPostSummary pps ON u.Id = pps.UserId
ORDER BY
    InfluenceScore DESC, u.Reputation DESC
LIMIT 100;