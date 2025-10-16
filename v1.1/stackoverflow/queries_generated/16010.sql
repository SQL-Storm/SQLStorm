-- {"query": "16010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 25685, "output_tokens": 24029} 

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(YEAR FROM AGE(u.LastAccessDate, u.CreationDate)) * 12 + 
            EXTRACT(MONTH FROM AGE(u.LastAccessDate, u.CreationDate)) AS TenureMonths,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRepRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRepRank,
        CASE 
            WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN 'Unknown'
            WHEN LENGTH(u.Location) > 20 THEN SUBSTRING(u.Location, 1, 20) || '...'
            ELSE u.Location
        END AS NormalizedLocation
    FROM Users u
    WHERE u.Reputation > 1000
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '2 years'
),
PostQualityScores AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        (p.Score * 10 + COALESCE(p.ViewCount, 0) / 100.0 + COALESCE(p.AnswerCount, 0) * 5) AS QualityScore,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.AnswerCount > 0 AND p.AcceptedAnswerId IS NULL THEN 0
            ELSE NULL
        END AS HasAcceptedAnswer,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS RollingAvgScore,
        NTILE(10) OVER (ORDER BY p.Score DESC) AS ScoreDecile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
        AND p.OwnerUserId IS NOT NULL
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostsInTag,
        AVG(p.Score) AS AvgScoreInTag,
        SUM(CASE WHEN p.Score >= 10 THEN 1 ELSE 0 END) AS HighQualityPosts,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT p.Id) DESC) AS ExpertRank
    FROM Posts p
    INNER JOIN Tags t ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    WHERE p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL
        AND t.Count > 100
    GROUP BY p.OwnerUserId, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 3
),
BadgeAchievements AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ' ORDER BY CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadgeNames,
        MAX(b.Date) AS LastBadgeDate,
        COUNT(DISTINCT b.Id)::float / NULLIF(EXTRACT(DAYS FROM AGE(MAX(b.Date), MIN(b.Date))), 0) AS BadgesPerDay
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY b.UserId
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.GlobalRepRank,
    uem.NormalizedLocation,
    uem.TenureMonths,
    COALESCE(ba.GoldBadges, 0) AS GoldBadgeCount,
    COALESCE(ba.SilverBadges, 0) AS SilverBadgeCount,
    COALESCE(ba.BronzeBadges, 0) AS BronzeBadgeCount,
    COALESCE(ba.GoldBadgeNames, 'None') AS TopBadges,
    AVG(pqs.QualityScore) FILTER (WHERE pqs.PostTypeId = 1) AS AvgQuestionQuality,
    AVG(pqs.QualityScore) FILTER (WHERE pqs.PostTypeId = 2) AS AvgAnswerQuality,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pqs.Score) AS MedianPostScore,
    COUNT(DISTINCT pqs.PostId) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN pqs.ScoreDecile <= 2 THEN pqs.PostId END) AS TopTierPosts,
    MAX(te.TagName) AS TopTag,
    MAX(te.PostsInTag) AS PostsInTopTag,
    COALESCE(
        (SELECT COUNT(DISTINCT c.Id) 
         FROM Comments c 
         WHERE c.UserId = uem.Id 
           AND c.CreationDate >= CURRENT_DATE - INTERVAL '1 year'), 
        0
    ) AS RecentComments,
    COALESCE(
        (SELECT AVG(v.BountyAmount)
         FROM Votes v
         INNER JOIN Posts p ON v.PostId = p.Id
         WHERE p.OwnerUserId = uem.Id
           AND v.VoteTypeId = 9
           AND v.BountyAmount IS NOT NULL),
        0
    ) AS AvgBountyReceived,
    CASE 
        WHEN uem.GlobalRepRank <= 100 THEN 'Elite'
        WHEN uem.GlobalRepRank <= 1000 THEN 'Expert'
        WHEN uem.GlobalRepRank <= 10000 THEN 'Advanced'
        ELSE 'Intermediate'
    END AS UserTier,
    COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPosts,
    ROUND(AVG(pqs.RollingAvgScore)::numeric, 2) AS ConsistencyScore
FROM UserEngagementMetrics uem
LEFT JOIN PostQualityScores pqs ON uem.Id = pqs.OwnerUserId
LEFT JOIN BadgeAchievements ba ON uem.Id = ba.UserId
LEFT JOIN TagExpertise te ON uem.Id = te.OwnerUserId AND te.ExpertRank = 1
LEFT JOIN Posts p2 ON p2.OwnerUserId = uem.Id AND p2.PostTypeId = 1
LEFT JOIN PostLinks pl ON pl.PostId = p2.Id
WHERE uem.GlobalRepRank <= 5000
    AND (pqs.QualityScore IS NULL OR pqs.QualityScore > 0)
    AND uem.TenureMonths >= 6
GROUP BY 
    uem.Id,
    uem.DisplayName,
    uem.Reputation,
    uem.GlobalRepRank,
    uem.NormalizedLocation,
    uem.TenureMonths,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.GoldBadgeNames
HAVING COUNT(DISTINCT pqs.PostId) >= 5
    AND AVG(pqs.QualityScore) > 10
ORDER BY 
    CASE WHEN AVG(pqs.QualityScore) IS NOT NULL THEN uem.Reputation / NULLIF(AVG(pqs.QualityScore), 0) END DESC NULLS LAST,
    uem.GlobalRepRank ASC,
    COUNT(DISTINCT pqs.PostId) DESC
LIMIT 500;
