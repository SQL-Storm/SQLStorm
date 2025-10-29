-- {"query": "1563.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3014}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Undisclosed') AS UserLocation,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE 0 END) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceivedOnPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceivedOnPosts,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND p.OwnerUserId = u.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location,
        u.Views, u.UpVotes, u.DownVotes
),
PostEventAggregates AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDateByHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS LastDeletedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.CreationDate END) AS LastProtectedDate,
        MIN(ph.CreationDate) AS FirstHistoryEventDate,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        (
            SELECT u.DisplayName
            FROM PostHistory ph_inner
            JOIN Users u ON u.Id = ph_inner.UserId
            WHERE ph_inner.PostId = ph.PostId AND ph_inner.PostHistoryTypeId = 10
            ORDER BY ph_inner.CreationDate DESC
            LIMIT 1
        ) AS LastCloserDisplayName,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12) AND ph.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR) THEN 1 ELSE 0 END) AS ClosedOrDeletedLastYearEventsCount
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Tags,
        p.CreationDate,
        CASE
            WHEN p.Tags IS NULL OR LENGTH(p.Tags) < 3 THEN 0
            ELSE cardinality(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))
        END AS NumTags,
        SUM(t.Count) AS TotalTagPopularity,
        SUM(CASE WHEN t.IsModeratorOnly = TRUE THEN 1 ELSE 0 END) AS ModeratorOnlyTagCount
    FROM Posts p
    LEFT JOIN Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.Id, p.Tags, p.CreationDate
),
QuestionAnswerMetrics AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerId,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        p.CreationDate AS QuestionCreationDate,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        COUNT(DISTINCT a.Id) AS ActualAnswerCount,
        MAX(CASE WHEN a.AcceptedAnswerId IS NOT NULL AND a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - p.CreationDate)) / (60 * 60 * 24)) AS AvgTimeToAnswerDays
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY
        p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
AggregatedRecentPostLinks AS (
    SELECT PostId, COUNT(DISTINCT RelatedPostId) AS DuplicateLinkCount
    FROM (
        SELECT PostId, RelatedPostId
        FROM PostLinks
        WHERE LinkTypeId = 3 AND CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
        UNION ALL
        SELECT RelatedPostId AS PostId, PostId AS RelatedPostId
        FROM PostLinks
        WHERE LinkTypeId = 3 AND CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
    ) AS AllDuplicateLinks
    GROUP BY PostId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserLocation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalPostScore,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadgesCount,
    AVG(p.Score) OVER (PARTITION BY uas.UserLocation) AS AvgScoreInLocation,
    RANK() OVER (PARTITION BY uas.UserLocation ORDER BY uas.Reputation DESC) AS RankInLocationByReputation,
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    pea.EditCount,
    pea.LastCloserDisplayName,
    pea.LastClosedDateByHistory,
    pta.NumTags,
    pta.TotalTagPopularity,
    pta.ModeratorOnlyTagCount,
    COALESCE(qam.AnswerCount, 0) AS StoredAnswerCount,
    COALESCE(qam.ActualAnswerCount, 0) AS ActualAnswerCount,
    COALESCE(qam.MaxAnswerScore, 0) AS MaxAnswerScoreForQuestion,
    COALESCE(qam.AvgTimeToAnswerDays, 0.0) AS AvgTimeToAnswerDays,
    CASE
        WHEN qam.QuestionId IS NOT NULL AND qam.ActualAnswerCount > 0 AND p.AcceptedAnswerId IS NOT NULL
        THEN 'ResolvedWithAccepted'
        WHEN qam.QuestionId IS NOT NULL AND qam.ActualAnswerCount > 0
        THEN 'ResolvedWithoutAccepted'
        WHEN qam.QuestionId IS NOT NULL AND qam.ActualAnswerCount = 0
        THEN 'UnresolvedQuestion'
        WHEN p.PostTypeId = 2 THEN 'AnswerPost'
        ELSE 'OtherPostType'
    END AS PostResolutionStatus,
    EXISTS (
        SELECT 1
        FROM PostHistory ph_corr
        WHERE ph_corr.PostId = p.Id
          AND ph_corr.UserId = uas.UserId
          AND ph_corr.PostHistoryTypeId IN (4, 5, 6)
          AND ph_corr.CreationDate > COALESCE(pea.LastClosedDateByHistory, CAST('1900-01-01' AS TIMESTAMP))
    ) AS EditedAfterClosure,
    (p.Score * 5.0 + COALESCE(p.ViewCount, 0) * 0.1 + COALESCE(qam.ActualAnswerCount, 0) * 2.0 + COALESCE(p.FavoriteCount, 0) * 3.0)
    / (1.0 + EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) / (3600.0 * 24.0 * 7.0) ) AS QuestionHotnessScoreWeeklyDecay,
    CASE WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) >= 3 THEN SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN p.Tags) - 2) ELSE NULL END AS FirstTag,
    ((uas.Reputation > 5000 AND p.Score > 10 AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH))
     OR (uas.TotalQuestions > 50 AND uas.TotalAnswers > 100 AND uas.UserLocation IS NOT NULL AND p.Body LIKE '%performance%')) AS HighImpactUserAndContent,
    pea.ClosedOrDeletedLastYearEventsCount,
    COALESCE(arlp.DuplicateLinkCount, 0) AS NumberOfDuplicateLinksAssociated
FROM Posts p
INNER JOIN UserActivitySummary uas ON p.OwnerUserId = uas.UserId
LEFT JOIN PostEventAggregates pea ON p.Id = pea.PostId
LEFT JOIN PostTagAnalysis pta ON p.Id = pta.PostId
LEFT JOIN QuestionAnswerMetrics qam ON p.Id = qam.QuestionId
LEFT JOIN UserBadgeSummary ubs ON uas.UserId = ubs.UserId
LEFT JOIN AggregatedRecentPostLinks arlp ON p.Id = arlp.PostId
WHERE
    p.PostTypeId IN (1, 2)
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5' YEAR)
    AND (
        p.Tags LIKE '%<sql>%' OR
        p.Tags LIKE '%<database>%' OR
        p.Tags LIKE '%<performance>%' OR
        p.Tags LIKE '%<query>%'
    )
    AND uas.Reputation > 1000
    AND ((p.ViewCount IS NOT NULL AND p.ViewCount > 500) OR p.Score > 5)
    AND p.Body IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_del
        WHERE ph_del.PostId = p.Id AND ph_del.PostHistoryTypeId = 12
          AND NOT EXISTS (
              SELECT 1 FROM PostHistory ph_undel
              WHERE ph_undel.PostId = ph_del.PostId AND ph_undel.PostHistoryTypeId = 13
                AND ph_undel.CreationDate > ph_del.CreationDate
          )
    )
ORDER BY
    QuestionHotnessScoreWeeklyDecay DESC,
    uas.Reputation DESC,
    p.CreationDate DESC
LIMIT 1000;