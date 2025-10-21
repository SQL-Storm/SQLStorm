-- {"query": "21038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 2423} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id 
        AND p.DeletedDate IS NULL
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    WHERE u.Reputation >= 100
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) >= 5
),
HighImpactPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.Title, 'No Title') AS Title,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
            ELSE 'Open'
        END AS PostStatus,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        FIRST_VALUE(p.Title) OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS FirstPostTitle,
        NTILE(4) OVER (ORDER BY p.ViewCount DESC) AS ViewQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.Score > 0
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND (p.DeletedDate IS NULL OR p.DeletedDate > CURRENT_DATE - INTERVAL '6 months')
),
EngagementMetrics AS (
    SELECT 
        au.UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS UpvotedComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(DISTINCT ph.Id) AS EditHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS ContentEdits,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM ActiveUsers au
    LEFT JOIN Comments c ON c.UserId = au.UserId 
        AND c.CreationDate >= au.UserCreationDate
        AND c.Score IS NOT NULL
    LEFT JOIN PostHistory ph ON ph.UserId = au.UserId 
        AND ph.PostId IN (SELECT PostId FROM HighImpactPosts WHERE OwnerUserId = au.UserId)
        AND ph.CreationDate >= au.UserCreationDate
    LEFT JOIN Votes v ON v.UserId = au.UserId 
        AND v.CreationDate >= au.UserCreationDate
        AND v.VoteTypeId IN (2, 3)
    GROUP BY au.UserId
),
TagAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Tags,
        CASE 
            WHEN p.Tags LIKE '%sql%' OR p.Tags LIKE '%database%' THEN 'Database'
            WHEN p.Tags LIKE '%python%' OR p.Tags LIKE '%javascript%' THEN 'Programming'
            WHEN p.Tags LIKE '%java%' OR p.Tags LIKE '%c++%' THEN 'Language'
            ELSE 'Other'
        END AS TagCategory,
        (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '>', ''))) AS TagCount,
        SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN p.Tags || '>') - 2) AS FirstTag,
        CASE 
            WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
            WHEN (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '>', ''))) >= 3 THEN 'MultiTag'
            ELSE 'SingleTag'
        END AS TagDensity
    FROM HighImpactPosts p
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL 
        AND p.Tags != ''
),
BadgeAchievements AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate,
        COUNT(DISTINCT SUBSTRING(b.Name FROM 1 FOR 1)) FILTER (WHERE b.TagBased = TRUE) AS DistinctTagBadges,
        STRING_AGG(DISTINCT b.Name, '; ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    INNER JOIN ActiveUsers au ON b.UserId = au.UserId
    WHERE b.Date >= au.UserCreationDate - INTERVAL '30 days'
    GROUP BY b.UserId
)
SELECT 
    au.UserId,
    u.DisplayName,
    au.Reputation,
    au.ReputationRank,
    au.QuestionCount,
    au.AnswerCount,
    au.AvgPostScore,
    COALESCE(hp.PostCount, 0) AS HighImpactPosts,
    em.TotalComments,
    em.UpvotesGiven - COALESCE(em.DownvotesGiven, 0) AS NetVotes,
    ba.TotalBadges,
    ba.GoldBadges,
    ta.TagCategory,
    ta.TagCount,
    CASE 
        WHEN au.Reputation > 10000 THEN 'Elite'
        WHEN au.Reputation > 1000 THEN 'Expert'
        WHEN au.Reputation > 100 THEN 'Active'
        ELSE 'Beginner'
    END AS ReputationTier,
    CONCAT(
        COALESCE(u.Location, 'Unknown'), 
        CASE WHEN u.Location IS NOT NULL AND u.WebsiteUrl IS NOT NULL THEN ', ' ELSE '' END,
        CASE WHEN u.WebsiteUrl IS NOT NULL THEN 'Has Website' ELSE '' END
    ) AS UserProfileInfo,
    CASE 
        WHEN hp.PostStatus = 'Closed' AND hp.ClosedDate IS NOT NULL 
             AND hp.ClosedDate < hp.PostCreationDate + INTERVAL '24 hours' 
        THEN 'Quick Close'
        WHEN ba.LatestBadgeDate IS NOT NULL 
             AND ba.LatestBadgeDate > CURRENT_DATE - INTERVAL '7 days'
        THEN 'Recent Achievement'
        WHEN em.ContentEdits > 5 AND au.PostCount > 20
        THEN 'Frequent Editor'
        ELSE 'Standard User'
    END AS UserCategory,
    ROW_NUMBER() OVER (
        PARTITION BY ta.TagCategory 
        ORDER BY (COALESCE(ba.GoldBadges, 0) * 10 + COALESCE(au.Reputation, 0)) DESC
    ) AS CategoryRank,
    PERCENT_RANK() OVER (ORDER BY COALESCE(au.PostCount, 0) * COALESCE(au.AvgPostScore, 0)) AS EngagementPercentile,
    -- Complex NULL-aware calculation
    GREATEST(
        COALESCE(hp.ViewCount, 0) / NULLIF(au.PostCount, 0),
        COALESCE(em.TotalComments, 0) / NULLIF(GREATEST(au.QuestionCount, 1), 0),
        0
    ) AS EngagementRatio
FROM ActiveUsers au
INNER JOIN Users u ON u.Id = au.UserId
LEFT JOIN HighImpactPosts hp ON hp.OwnerUserId = au.UserId 
    AND hp.PostCreationDate >= au.UserCreationDate
    AND hp.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
LEFT JOIN EngagementMetrics em ON em.UserId = au.UserId
LEFT JOIN BadgeAchievements ba ON ba.UserId = au.UserId
LEFT JOIN (
    SELECT PostId, TagCategory, TagCount,
           ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY TagCount DESC) as rn
    FROM TagAnalysis
    WHERE TagDensity = 'MultiTag'
) ta ON ta.PostId = hp.PostId AND ta.rn = 1
WHERE au.PostCount > (
    SELECT AVG(PostCount) FROM ActiveUsers
)
    AND (u.Location IS NULL OR u.Location != '')
    AND NOT EXISTS (
        SELECT 1 FROM Votes v2 
        WHERE v2.UserId = au.UserId 
            AND v2.VoteTypeId = 3 
            AND v2.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
            GROUP BY v2.UserId 
            HAVING COUNT(*) > 10
    )
UNION ALL
SELECT 
    NULL AS UserId,
    'AGGREGATE STATS' AS DisplayName,
    AVG(au.Reputation)::int AS Reputation,
    NULL AS ReputationRank,
    AVG(au.QuestionCount)::int AS QuestionCount,
    AVG(au.AnswerCount)::int AS AnswerCount,
    AVG(au.AvgPostScore) AS AvgPostScore,
    AVG(COALESCE(hp.PostCount, 0))::int AS HighImpactPosts,
    AVG(COALESCE(em.TotalComments, 0))::int AS TotalComments,
    AVG(COALESCE(em.UpvotesGiven, 0) - COALESCE(em.DownvotesGiven, 0))::int AS NetVotes,
    AVG(COALESCE(ba.TotalBadges, 0))::int AS TotalBadges,
    AVG(COALESCE(ba.GoldBadges, 0))::int AS GoldBadges,
    'OVERALL' AS TagCategory,
    AVG(COALESCE(ta.TagCount, 0))::int AS TagCount,
    'Summary' AS ReputationTier,
    'Platform Aggregate' AS UserProfileInfo,
    NULL AS UserCategory,
    NULL AS CategoryRank,
    NULL AS EngagementPercentile,
    AVG(
        COALESCE(
            GREATEST(
                COALESCE(hp.ViewCount, 0) / NULLIF(au.PostCount, 0),
                COALESCE(em.TotalComments, 0) / NULLIF(GREATEST(au.QuestionCount, 1), 0),
                0
            ), 0
        )
    ) AS EngagementRatio
FROM ActiveUsers au
LEFT JOIN HighImpactPosts hp ON hp.OwnerUserId = au.UserId
LEFT JOIN EngagementMetrics em ON em.UserId = au.UserId
LEFT JOIN BadgeAchievements ba ON ba.UserId = au.UserId
LEFT JOIN TagAnalysis ta ON ta.PostId = hp.PostId
ORDER BY 
    CASE WHEN UserId IS NULL THEN 0 ELSE 1 END,
    Reputation DESC,
    EngagementRatio DESC NULLS LAST
LIMIT 1000;
