-- {"query": "22080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1227} 
WITH UserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.TagBased = true) AS TagBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount END) AS TotalAnswersReceived,
        COUNT(CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 1 END) AS TotalAnswersGiven,
        COALESCE(AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/86400), 0) AS AvgPostLifespanDays,
        STRING_AGG(DISTINCT substring(p.Tags, 2, length(p.Tags)-2), ', ') FILTER (WHERE p.PostTypeId = 1) AS DistinctTags
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
VoteStats AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesReceived,
        COUNT(DISTINCT v.PostId) AS PostsVotedOn,
        AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBountyAmount
    FROM Votes v
    GROUP BY v.UserId
),
CombinedStats AS (
    SELECT 
        ub.UserId,
        ub.DisplayName,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBadges,
        ps.TotalPosts,
        ps.AvgQuestionScore,
        ps.TotalAnswersReceived,
        ps.TotalAnswersGiven,
        ps.AvgPostLifespanDays,
        ps.DistinctTags,
        vs.UpvotesReceived,
        vs.DownvotesReceived,
        vs.PostsVotedOn,
        vs.AvgBountyAmount,
        (COALESCE(ub.TotalBadges, 0) * 100 + COALESCE(ps.TotalPosts, 0) * 10 + COALESCE(vs.UpvotesReceived, 0) - COALESCE(vs.DownvotesReceived, 0)) AS OverallScore
    FROM UserBadges ub
    FULL OUTER JOIN PostStats ps ON ub.UserId = ps.OwnerUserId
    FULL OUTER JOIN VoteStats vs ON ub.UserId = vs.UserId OR ps.OwnerUserId = vs.UserId
    WHERE ub.UserId IS NOT NULL OR ps.OwnerUserId IS NOT NULL OR vs.UserId IS NOT NULL
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY OverallScore DESC, TotalBadges DESC) AS Rank,
        CASE WHEN AvgQuestionScore IS NULL THEN 'No Questions' ELSE TO_CHAR(AvgQuestionScore, '999.99') END AS FormattedScore
    FROM CombinedStats
)
SELECT 
    ru.Rank,
    ru.DisplayName,
    ru.OverallScore,
    ru.TotalBadges,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    COALESCE(LENGTH(ru.TagBadges), 0) AS TagBadgesLength,
    ru.TotalPosts,
    ru.AvgQuestionScore,
    ru.TotalAnswersReceived,
    ru.TotalAnswersGiven,
    ru.AvgPostLifespanDays,
    ru.UpvotesReceived - ru.DownvotesReceived AS NetUpvotes,
    ru.PostsVotedOn,
    ru.AvgBountyAmount,
    ru.FormattedScore,
    CASE 
        WHEN ru.TotalAnswersGiven > ru.TotalPosts THEN 'Answer Enthusiast'
        WHEN ru.GoldBadges > 0 THEN 'Elite User'
        ELSE 'Regular User'
    END AS UserType,
    ARRAY_LENGTH(STRING_TO_ARRAY(ru.DistinctTags, ', '), 1) AS NumDistinctTags
FROM RankedUsers ru
WHERE ru.Rank <= 100
    AND EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = ru.UserId 
        AND p.PostTypeId = 1 
        AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL)
    )
UNION
SELECT 
    NULL AS Rank,
    'Anonymous' AS DisplayName,
    NULL AS OverallScore,
    NULL AS TotalBadges,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS TagBadgesLength,
    NULL AS TotalPosts,
    NULL AS AvgQuestionScore,
    NULL AS TotalAnswersReceived,
    NULL AS TotalAnswersGiven,
    NULL AS AvgPostLifespanDays,
    NULL AS NetUpvotes,
    NULL AS PostsVotedOn,
    NULL AS AvgBountyAmount,
    NULL AS FormattedScore,
    'No Posts' AS UserType,
    NULL AS NumDistinctTags
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Id IN (SELECT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL))
ORDER BY Rank NULLS LAST;