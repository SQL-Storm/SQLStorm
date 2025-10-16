-- {"query": "28049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1639} 

WITH UserBadges AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
PostStats AS (
    SELECT 
        OwnerUserId,
        COUNT(*) AS TotalPosts,
        AVG(Score) AS AvgPostScore,
        SUM(ViewCount) AS TotalViews,
        COUNT(AcceptedAnswerId) AS AcceptedAnswers
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
),
CommentRank AS (
    SELECT 
        UserId,
        SUM(Score) AS TotalCommentScore,
        RANK() OVER (ORDER BY SUM(Score) DESC) AS CommentRank
    FROM Comments
    GROUP BY UserId
),
VoteAnalysis AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(CASE WHEN VoteTypeId = 8 THEN 1 END) AS BountiesStarted
    FROM Votes
    GROUP BY UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(ub.GoldBadges, 0) + COALESCE(ub.SilverBadges, 0) * 0.5 + COALESCE(ub.BronzeBadges, 0) * 0.25 AS WeightedBadgeScore,
    ps.TotalPosts,
    ps.AvgPostScore,
    ps.TotalViews,
    ps.AcceptedAnswers,
    cr.TotalCommentScore,
    cr.CommentRank,
    va.Upvotes,
    va.Downvotes,
    va.BountiesStarted,
    (SELECT p.Title FROM Posts p WHERE p.OwnerUserId = u.Id ORDER BY p.CreationDate DESC LIMIT 1) AS LatestPostTitle,
    (SELECT COUNT(DISTINCT ph.PostHistoryTypeId) FROM PostHistory ph WHERE ph.UserId = u.Id) AS UniqueEditTypes,
    RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalReputationRank,
    DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyReputationRank,
    COALESCE(STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 15), '; '), 'N/A') AS FrequentTags,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND LinkTypeId = 3) AS DuplicateMarkings,
    CASE 
        WHEN u.Reputation > 100000 THEN 'Legendary' 
        WHEN u.Reputation > 50000 THEN 'Epic' 
        WHEN u.Reputation > 20000 THEN 'Veteran' 
        ELSE 'Regular' 
    END AS ReputationTier,
    COALESCE(ub.LastBadgeDate, u.CreationDate) AS LastActivity,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.Score > 10) OVER (PARTITION BY u.Id) AS HighQualityAnswers,
    AVG(LENGTH(p.Body)) OVER () AS AvgPostLengthGlobal,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) AS RepliesToUserPosts
FROM Users u
LEFT JOIN UserBadges ub ON u.Id = ub.UserId
LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
LEFT JOIN CommentRank cr ON u.Id = cr.UserId
LEFT JOIN VoteAnalysis va ON u.Id = va.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Tags t ON EXISTS (
    SELECT 1 FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    WHERE tag = t.TagName
)
WHERE u.Reputation > 1000
    AND (ps.TotalPosts > 50 OR cr.TotalCommentScore > 200)
    AND u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
GROUP BY u.Id, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ps.TotalPosts, ps.AvgPostScore, 
    ps.TotalViews, ps.AcceptedAnswers, cr.TotalCommentScore, cr.CommentRank, va.Upvotes, 
    va.Downvotes, va.BountiesStarted, ub.LastBadgeDate, p.Id
HAVING COUNT(DISTINCT p.PostTypeId) > 1 OR MAX(p.Score) > 100
ORDER BY u.Reputation DESC
LIMIT 100;
