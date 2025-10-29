-- {"query": "1968.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2624}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        MAX(p.CreationDate) AS LatestPostDate,
        MAX(c.CreationDate) AS LatestCommentDate,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS PostEditCountOnOwnPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND p.Id IS NOT NULL AND ph.PostId = p.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate AS PostLastActivityDate,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 3600.0 AS EngagementDurationHours,
        (SELECT AVG(c_sub.Score) FROM Comments c_sub WHERE c_sub.PostId = p.Id) AS AvgCommentScore,
        (SELECT MAX(v_sub.CreationDate) FROM Votes v_sub WHERE v_sub.PostId = p.Id) AS LatestVoteDate,
        CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2)
),
UserBadgeMilestones AS (
    SELECT
        b.UserId,
        MIN(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS FirstGoldBadgeDate,
        MAX(b.Date) AS MostRecentBadgeDate,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount
    FROM
        Badges b
    GROUP BY
        b.UserId
),
RecentModerationActivity AS (
    SELECT
        ph.PostId,
        ph.UserId AS ModeratorUserId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
        AND ph.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        TRIM(BOTH '<>' FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName
    FROM
        Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 AND LENGTH(p.Tags) > 2
),
HighlyVotedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score AS QuestionScore,
        p.CreationDate AS QuestionCreationDate,
        COALESCE(p.FavoriteCount, 0) AS QuestionFavoriteCount,
        p.ViewCount AS QuestionViewCount,
        (
            SELECT vt.Name
            FROM Votes v_inner
            JOIN VoteTypes vt ON v_inner.VoteTypeId = vt.Id
            WHERE v_inner.PostId = p.Id AND v_inner.VoteTypeId IN (2, 3)
            GROUP BY vt.Name
            ORDER BY COUNT(v_inner.Id) DESC
            LIMIT 1
        ) AS MostFrequentVoteType
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 AND p.Score > 50 AND p.ViewCount > 1000
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalComments,
    uas.TotalPostScore,
    uas.TotalCommentScore,
    uas.TotalBadges,
    ubm.FirstGoldBadgeDate,
    ubm.MostRecentBadgeDate,
    ubm.GoldBadgeCount,
    ubm.SilverBadgeCount,
    ubm.BronzeBadgeCount,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PrevUserReputation,
    RANK() OVER (ORDER BY u.Reputation DESC, uas.TotalPostScore DESC) AS ReputationRank,
    CASE
        WHEN uas.TotalQuestions > 0 THEN CAST(uas.TotalAnswers AS DECIMAL) / uas.TotalQuestions
        ELSE 0
    END AS AnswerToQuestionRatio,
    COALESCE(ROUND(CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)) / 86400.0 AS numeric), 2), 9999.0) AS DaysSinceLastAccess,
    COALESCE(SUM(pe.PostScore), 0) AS OwnedPostsTotalScore,
    COALESCE(AVG(pe.EngagementDurationHours), 0.0) AS AvgOwnedPostEngagementDuration,
    COUNT(pe.PostId) FILTER (WHERE pe.HasAcceptedAnswer) AS OwnedQuestionsWithAcceptedAnswer,
    COUNT(pe.PostId) FILTER (WHERE pe.HasAcceptedAnswer AND pe.PostTypeId = 1) AS AcceptedAnswersOwnedCount,
    MAX(pe.LatestVoteDate) AS LatestVoteOnOwnedPost,
    (
        SELECT ta.TagName
        FROM PostTagAnalysis ta
        WHERE ta.PostId IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = u.Id AND p_sub.PostTypeId = 1)
        GROUP BY ta.TagName
        ORDER BY COUNT(ta.TagName) DESC, MAX(ta.PostId) DESC
        LIMIT 1
    ) AS MostActiveTag,
    MAX(CASE WHEN rma.PostHistoryTypeId IN (10, 12, 14) THEN 'YES' ELSE 'NO' END) AS HadRecentClosedOrDeletedPost,
    STRING_AGG(DISTINCT hq.Title, ' ||| ') FILTER (WHERE hq.Title IS NOT NULL) AS HighlyVotedQuestionsContributedTo,
    (
        u.Reputation * 0.5 +
        uas.TotalPostScore * 0.2 +
        uas.TotalComments * 0.05 +
        uas.TotalBadges * 0.1 +
        COALESCE(ubm.GoldBadgeCount, 0) * 0.15 +
        (SELECT COALESCE(SUM(v.BountyAmount), 0) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) * 0.01 +
        COALESCE(SUM(pe.FavoriteCount), 0) * 0.02
    ) AS InfluenceScore
FROM
    Users u
INNER JOIN UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN UserBadgeMilestones ubm ON u.Id = ubm.UserId
LEFT JOIN PostEngagementMetrics pe ON u.Id = pe.OwnerUserId
LEFT JOIN HighlyVotedQuestions hq ON u.Id = hq.OwnerUserId
LEFT JOIN RecentModerationActivity rma ON pe.PostId = rma.PostId AND rma.rn = 1
WHERE
    u.Reputation > 1000
    AND u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    AND (uas.TotalPosts > 10 OR uas.TotalComments > 50)
    AND u.Location IS NOT NULL
    AND LENGTH(TRIM(u.AboutMe)) > 50
    AND (u.DisplayName LIKE '%Dev%' OR u.DisplayName LIKE '%Code%')
    AND EXISTS (
        SELECT 1
        FROM Badges b_sub
        WHERE b_sub.UserId = u.Id
          AND LOWER(b_sub.Name) LIKE LOWER('%Answer%')
          AND b_sub.Date >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
    )
GROUP BY
    u.Id, u.DisplayName, u.Reputation, uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers,
    uas.TotalComments, uas.TotalPostScore, uas.TotalCommentScore, uas.TotalBadges,
    ubm.FirstGoldBadgeDate, ubm.MostRecentBadgeDate, ubm.GoldBadgeCount, ubm.SilverBadgeCount,
    ubm.BronzeBadgeCount, u.LastAccessDate, u.AboutMe, u.CreationDate
HAVING
    COUNT(pe.PostId) FILTER (WHERE pe.HasAcceptedAnswer) >= 1 OR COUNT(hq.QuestionId) >= 1
ORDER BY
    InfluenceScore DESC, ReputationRank ASC
LIMIT 1000;