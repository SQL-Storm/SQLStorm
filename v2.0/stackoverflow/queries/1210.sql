WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL), 0.0) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COUNT(v.Id) AS TotalVotesGivenByOwner,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        CAST((EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)) / 86400) AS int) AS DaysSinceLastAccess
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 0 OR COUNT(DISTINCT c.Id) > 0
),
QuestionDetails AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        (SELECT COUNT(ph.Id)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
        ) AS EditCount,
        (SELECT COUNT(ph.Id)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11)
        ) AS CloseReopenEvents,
        COALESCE(SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2), '') AS PrimaryTag,
        LENGTH(REPLACE(REPLACE(p.Body, '<pre><code>', ''), '</code></pre>', '')) AS BodyTextLength,
        CASE
            WHEN p.Body LIKE '%<pre><code>%' AND p.Body LIKE '%</code></pre>%' THEN TRUE
            ELSE FALSE
        END AS HasCodeSnippet,
        p.LastActivityDate,
        p.CommunityOwnedDate,
        ph_closed.CreationDate AS ClosedTimestamp,
        crt.Name AS CloseReason
    FROM Posts p
    LEFT JOIN (
        SELECT sub.PostId, sub.CreationDate, sub.Comment
        FROM (
            SELECT
                ph.PostId,
                ph.CreationDate,
                ph.Comment,
                ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
            FROM PostHistory ph
            WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
        ) sub
        WHERE sub.rn = 1
    ) ph_closed ON p.Id = ph_closed.PostId
    LEFT JOIN CloseReasonTypes crt ON ph_closed.Comment = CAST(crt.Id AS text)
    WHERE p.PostTypeId = 1
),
AnswerQuality AS (
    SELECT
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswerOwnerUserId,
        p.Id AS AnswerId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        COUNT(c.Id) AS AnswerCommentCount,
        AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS AvgAnswerCommentScore,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate) AS RankByScoreForQuestion
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId, p.OwnerUserId, p.Id, p.Score, p.CreationDate
),
BadgeMilestones AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeAwardDate,
        u.Reputation AS UserReputationAtBadge,
        DENSE_RANK() OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date) AS BadgeRankForClass,
        LEAD(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS NextBadgeAwardDate,
        CAST((EXTRACT(EPOCH FROM (LEAD(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) - b.Date)) / 86400) AS int) AS DaysUntilNextBadge
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE b.Class IN (1, 2)
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS TotalLinkedPosts,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS TotalDuplicateMarkers,
        COUNT(DISTINCT pl.RelatedPostId) AS UniqueRelatedPosts
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
QuestionStatsExtended AS (
    SELECT
        qd.PostId,
        qd.OwnerUserId,
        qd.Title,
        qd.PrimaryTag,
        qd.PostScore,
        qd.ViewCount,
        qd.FavoriteCount,
        qd.AnswerCount,
        qd.EditCount,
        qd.CloseReopenEvents,
        qd.HasCodeSnippet,
        qd.ClosedTimestamp,
        qd.CloseReason,
        pla.TotalLinkedPosts,
        pla.TotalDuplicateMarkers,
        MAX(CASE WHEN aq.RankByScoreForQuestion = 1 THEN 1 ELSE 0 END) AS HasTopAnswer,
        AVG(aq.AnswerScore) AS AvgAnswerScoreForQuestion,
        SUM(aq.AnswerScore) AS TotalAnswerScoreForQuestion,
        COUNT(aq.AnswerId) AS ActualAnswerCount,
        NTILE(5) OVER (PARTITION BY qd.PrimaryTag ORDER BY qd.ViewCount DESC) AS ViewCountQuintileByTag,
        RANK() OVER (PARTITION BY qd.PrimaryTag ORDER BY qd.PostScore DESC, qd.FavoriteCount DESC) AS PostRankByTag,
        qd.PostCreationDate
    FROM QuestionDetails qd
    LEFT JOIN AnswerQuality aq ON qd.PostId = aq.QuestionId
    LEFT JOIN PostLinkAnalysis pla ON qd.PostId = pla.PostId
    GROUP BY
        qd.PostId,
        qd.OwnerUserId,
        qd.Title,
        qd.PrimaryTag,
        qd.PostScore,
        qd.ViewCount,
        qd.FavoriteCount,
        qd.AnswerCount,
        qd.EditCount,
        qd.CloseReopenEvents,
        qd.HasCodeSnippet,
        qd.ClosedTimestamp,
        qd.CloseReason,
        pla.TotalLinkedPosts,
        pla.TotalDuplicateMarkers,
        qd.PostCreationDate
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgPostScore,
    ua.DaysSinceLastAccess,
    qse.PostId AS RelatedPostId,
    qse.Title AS RelatedPostTitle,
    qse.PrimaryTag,
    qse.PostScore AS RelatedPostScore,
    qse.ViewCount AS RelatedPostViewCount,
    qse.FavoriteCount AS RelatedPostFavoriteCount,
    qse.ActualAnswerCount,
    qse.EditCount AS RelatedPostEditCount,
    qse.CloseReopenEvents,
    qse.HasCodeSnippet,
    qse.ClosedTimestamp,
    COALESCE(qse.CloseReason, 'N/A') AS FinalCloseReason,
    qse.TotalLinkedPosts,
    qse.TotalDuplicateMarkers,
    COALESCE(qse.HasTopAnswer, 0) AS HasTopAnswerFlag,
    COALESCE(qse.AvgAnswerScoreForQuestion, 0.0) AS AvgAnswerScoreForPost,
    COALESCE(qse.TotalAnswerScoreForQuestion, 0) AS TotalAnswerScoreForPost,
    qse.ViewCountQuintileByTag,
    qse.PostRankByTag,
    bm.BadgeName AS MajorBadgeName,
    bm.BadgeClass AS MajorBadgeClass,
    bm.BadgeAwardDate,
    bm.DaysUntilNextBadge,
    CAST((ua.Reputation * (qse.PostScore + COALESCE(qse.TotalAnswerScoreForQuestion, 0.0)) / (ua.DaysSinceLastAccess + 1) *
        CASE
            WHEN qse.HasCodeSnippet THEN 1.25
            WHEN LOWER(qse.PrimaryTag) LIKE '%sql%' OR LOWER(qse.PrimaryTag) LIKE '%database%' THEN 1.5
            WHEN COALESCE(qse.TotalDuplicateMarkers,0) > 0 THEN 0.8
            ELSE 1.0
        END
    ) AS NUMERIC(18,4)) AS EngagementMetric,
    LAG(ua.Reputation, 1, 0) OVER (PARTITION BY ua.UserId ORDER BY qse.PostCreationDate NULLS FIRST) AS PreviousActivityReputation,
    RANK() OVER (ORDER BY ua.Reputation DESC, ua.TotalPosts DESC,
        CAST((ua.Reputation * (qse.PostScore + COALESCE(qse.TotalAnswerScoreForQuestion, 0.0)) / (ua.DaysSinceLastAccess + 1) *
            CASE
                WHEN qse.HasCodeSnippet THEN 1.25
                WHEN LOWER(qse.PrimaryTag) LIKE '%sql%' OR LOWER(qse.PrimaryTag) LIKE '%database%' THEN 1.5
                WHEN COALESCE(qse.TotalDuplicateMarkers,0) > 0 THEN 0.8
                ELSE 1.0
            END
        ) AS NUMERIC(18,4))
    ) AS GlobalUserRank
FROM UserActivity ua
LEFT JOIN QuestionStatsExtended qse ON ua.UserId = qse.OwnerUserId
LEFT JOIN BadgeMilestones bm ON ua.UserId = bm.UserId
WHERE
    ua.Reputation > 7500
    AND qse.PostId IS NOT NULL
    AND (
        (qse.HasCodeSnippet AND qse.PostScore > 100 AND qse.ViewCount > 50000)
        OR (qse.PrimaryTag IN ('javascript', 'python', 'java', 'c#', 'c++', 'html', 'css') AND qse.ViewCount > 30000 AND qse.ActualAnswerCount > 7 AND qse.EditCount < 5)
        OR (qse.ClosedTimestamp IS NOT NULL AND qse.CloseReason IN ('Needs details or clarity', 'Needs more focus') AND qse.PostRankByTag <= 10)
    )
    AND ua.DaysSinceLastAccess < 120
    AND bm.BadgeClass = 1
    AND (bm.DaysUntilNextBadge IS NULL OR bm.DaysUntilNextBadge > 90)
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_del
        WHERE ph_del.PostId = qse.PostId
          AND ph_del.PostHistoryTypeId = 12
          AND ph_del.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    )

UNION ALL

SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgPostScore,
    ua.DaysSinceLastAccess,
    NULL AS RelatedPostId,
    'N/A' AS RelatedPostTitle,
    'N/A' AS PrimaryTag,
    NULL AS RelatedPostScore,
    NULL AS RelatedPostViewCount,
    NULL AS RelatedPostFavoriteCount,
    NULL AS ActualAnswerCount,
    NULL AS RelatedPostEditCount,
    NULL AS CloseReopenEvents,
    FALSE AS HasCodeSnippet,
    NULL AS ClosedTimestamp,
    'N/A' AS FinalCloseReason,
    NULL AS TotalLinkedPosts,
    NULL AS TotalDuplicateMarkers,
    NULL AS HasTopAnswerFlag,
    NULL AS AvgAnswerScoreForPost,
    NULL AS TotalAnswerScoreForPost,
    NULL AS ViewCountQuintileByTag,
    NULL AS PostRankByTag,
    bm.BadgeName AS MajorBadgeName,
    bm.BadgeClass AS MajorBadgeClass,
    bm.BadgeAwardDate,
    bm.DaysUntilNextBadge,
    CAST((ua.Reputation * (ua.TotalAnswers * ua.AvgPostScore) / (ua.DaysSinceLastAccess + 1) *
        CASE
            WHEN ua.TotalAnswers > ua.TotalQuestions AND ua.AvgPostScore > 15 THEN 1.4
            WHEN ua.TotalComments > 100 AND ua.TotalAnswers > 50 THEN 1.1
            ELSE 1.0
        END
    ) AS NUMERIC(18,4)) AS EngagementMetric,
    LAG(ua.Reputation, 1, 0) OVER (PARTITION BY ua.UserId ORDER BY bm.BadgeAwardDate NULLS FIRST) AS PreviousActivityReputation,
    RANK() OVER (ORDER BY ua.TotalAnswers DESC, ua.AvgPostScore DESC,
        CAST((ua.Reputation * (ua.TotalAnswers * ua.AvgPostScore) / (ua.DaysSinceLastAccess + 1) *
            CASE
                WHEN ua.TotalAnswers > ua.TotalQuestions AND ua.AvgPostScore > 15 THEN 1.4
                WHEN ua.TotalComments > 100 AND ua.TotalAnswers > 50 THEN 1.1
                ELSE 1.0
            END
        ) AS NUMERIC(18,4))
    ) AS GlobalUserRank
FROM UserActivity ua
JOIN BadgeMilestones bm ON ua.UserId = bm.UserId
WHERE
    ua.Reputation > 2000
    AND ua.TotalAnswers > (ua.TotalQuestions * 1.5)
    AND ua.AvgPostScore > 8
    AND ua.DaysSinceLastAccess < 60
    AND bm.BadgeClass = 2
    AND bm.BadgeAwardDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
    AND EXISTS (
        SELECT 1
        FROM Posts p_ans
        WHERE p_ans.OwnerUserId = ua.UserId
          AND p_ans.PostTypeId = 2
          AND p_ans.Score > 50
          AND p_ans.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months')
    )
ORDER BY GlobalUserRank ASC, EngagementMetric DESC
LIMIT 5000;