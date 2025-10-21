-- {"query": "17016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2293}

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.CreationDate)) AS YearsOnSite,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) FILTER (WHERE t.Count > 100) AS PopularTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name
    ) tag_split ON p.PostTypeId = 1
    LEFT JOIN Tags t ON tag_split.tag_name = t.TagName
    WHERE u.CreationDate < CURRENT_DATE - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
BadgeAnalysis AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (b.Date - LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date)))) AS MedianBadgeInterval
    FROM Badges b
    GROUP BY b.UserId
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Open'
        END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC NULLS LAST) AS GlobalScoreRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.CreationDate BETWEEN CURRENT_DATE - INTERVAL '2 years' AND CURRENT_DATE - INTERVAL '1 month'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId
),
LinkedPostNetwork AS (
    SELECT 
        pl1.PostId,
        COUNT(DISTINCT pl1.RelatedPostId) AS DirectLinks,
        COUNT(DISTINCT pl2.RelatedPostId) AS SecondDegreeLinks,
        EXISTS (
            SELECT 1 
            FROM PostLinks pl3 
            WHERE pl3.PostId = pl1.RelatedPostId 
            AND pl3.RelatedPostId = pl1.PostId
        ) AS HasBidirectionalLink
    FROM PostLinks pl1
    LEFT JOIN PostLinks pl2 ON pl1.RelatedPostId = pl2.PostId AND pl2.LinkTypeId = 1
    GROUP BY pl1.PostId
)
SELECT 
    um.DisplayName,
    um.Reputation,
    UPPER(SUBSTRING(um.Location FROM 1 FOR 3)) || REPEAT('*', GREATEST(0, LENGTH(um.Location) - 3)) AS MaskedLocation,
    um.YearsOnSite,
    um.TotalPosts,
    um.Questions,
    um.Answers,
    ROUND(um.AvgPostScore::numeric, 2) AS AvgPostScore,
    COALESCE(ba.GoldBadges, 0) + COALESCE(ba.SilverBadges, 0) * 0.5 + COALESCE(ba.BronzeBadges, 0) * 0.25 AS WeightedBadgeScore,
    CASE 
        WHEN ba.LastBadgeDate > CURRENT_DATE - INTERVAL '30 days' THEN 'Active'
        WHEN ba.LastBadgeDate > CURRENT_DATE - INTERVAL '90 days' THEN 'Recent'
        ELSE 'Inactive'
    END AS BadgeActivity,
    COUNT(DISTINCT pe.PostId) AS HighQualityPosts,
    SUM(CASE WHEN pe.UserPostRank <= 3 THEN pe.Score ELSE 0 END) AS Top3PostsScore,
    AVG(pe.ViewCount) FILTER (WHERE pe.ViewCount IS NOT NULL AND pe.ViewCount > 0) AS AvgViewsPerPost,
    COALESCE(SUM(lpn.DirectLinks), 0) AS TotalDirectLinks,
    COALESCE(SUM(lpn.SecondDegreeLinks), 0) AS TotalSecondDegreeLinks,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY pe.Score) AS Score75thPercentile,
    STRING_AGG(
        CASE WHEN pe.GlobalScoreRank <= 100 THEN 'Post#' || pe.PostId::text END, 
        '; ' 
        ORDER BY pe.GlobalScoreRank
    ) AS Top100Posts,
    COALESCE(um.PopularTags, 'No popular tags') AS UserPopularTags,
    CASE 
        WHEN um.Reputation >= 10000 AND ba.GoldBadges >= 5 THEN 'Elite'
        WHEN um.Reputation >= 5000 OR ba.GoldBadges >= 2 THEN 'Expert'
        WHEN um.Reputation >= 1000 OR ba.SilverBadges >= 5 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    (
        SELECT COUNT(DISTINCT c2.Id)
        FROM Comments c2
        WHERE c2.UserId = um.Id
        AND c2.Score > (SELECT AVG(Score) FROM Comments WHERE Score IS NOT NULL)
    ) AS AboveAvgComments
FROM UserMetrics um
LEFT JOIN BadgeAnalysis ba ON um.Id = ba.UserId
LEFT JOIN PostEngagement pe ON um.Id = pe.OwnerUserId AND pe.Score > 0
LEFT JOIN LinkedPostNetwork lpn ON pe.PostId = lpn.PostId
WHERE um.TotalPosts > 0
    AND (um.Questions > 0 OR um.Answers > 0)
    AND NOT EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = um.Id 
        AND ph.PostHistoryTypeId = 12 
        AND ph.CreationDate > CURRENT_DATE - INTERVAL '3 months'
    )
GROUP BY 
    um.Id, um.DisplayName, um.Reputation, um.Location, um.YearsOnSite,
    um.TotalPosts, um.Questions, um.Answers, um.AvgPostScore, um.PopularTags,
    ba.GoldBadges, ba.SilverBadges, ba.BronzeBadges, ba.LastBadgeDate, ba.MedianBadgeInterval
HAVING COUNT(DISTINCT pe.PostId) > 0 OR um.Reputation > 100
ORDER BY 
    WeightedBadgeScore DESC NULLS LAST,
    um.Reputation DESC,
    TotalDirectLinks DESC NULLS LAST
LIMIT 100;
