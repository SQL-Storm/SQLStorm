-- {"query": "16062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2206}

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(SUBSTRING(u.Location, 1, 20), 'Unknown') ORDER BY u.Reputation DESC) as LocationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as BadgeRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) as PrevUserReputation,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) as NextUserReputation
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= '2020-01-01'
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    LEFT OUTER JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE u.Reputation > 100
        AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
        AND u.CreationDate >= '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 0
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(LENGTH(p.Body), 0) as BodyLength,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END as PostStatus,
        COALESCE(u.DisplayName, p.OwnerDisplayName, 'Anonymous') as AuthorName,
        STRING_AGG(DISTINCT COALESCE(c.Text, ''), ' | ') as ConcatenatedComments,
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id 
         AND ph.PostHistoryTypeId IN (4, 5, 6)) as EditCount,
        (SELECT COALESCE(AVG(v2.BountyAmount), 0)
         FROM Votes v2
         WHERE v2.PostId = p.Id 
         AND v2.VoteTypeId = 8) as AvgBounty,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 86400.0 as DaysActive,
        CASE 
            WHEN p.Tags LIKE '%<sql>%' THEN 1
            WHEN p.Tags LIKE '%<python>%' THEN 2
            WHEN p.Tags LIKE '%<javascript>%' THEN 3
            ELSE 0
        END as PrimaryTagCategory
    FROM Posts p
    LEFT OUTER JOIN Users u ON p.OwnerUserId = u.Id
    LEFT OUTER JOIN Comments c ON p.Id = c.PostId AND c.Score > 0
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
        AND (p.Score > 5 OR p.ViewCount > 1000 OR p.FavoriteCount > 0)
    GROUP BY p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount, 
             p.Body, p.ClosedDate, p.AcceptedAnswerId, u.DisplayName, 
             p.OwnerDisplayName, p.LastActivityDate, p.CreationDate, p.Tags
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        COUNT(DISTINCT pl.PostId) as LinkedPostCount,
        AVG(p.Score) as AvgTagScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) as MedianViews,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0) as AcceptanceRate
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT OUTER JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE t.Count > 100
        AND t.IsModeratorOnly = 0
    GROUP BY t.TagName, t.Count
)
SELECT 
    uem.DisplayName,
    COALESCE(NULLIF(TRIM(uem.Location), ''), 'Not Specified') as CleanedLocation,
    uem.Reputation,
    uem.PostCount,
    uem.BadgeCount,
    uem.QuestionScore + uem.AnswerScore as TotalScore,
    ROUND(CAST(uem.QuestionScore AS NUMERIC) / NULLIF(uem.AnswerScore, 0), 2) as QuestionAnswerRatio,
    cpa.PostStatus,
    COUNT(DISTINCT cpa.PostId) as AnalyzedPosts,
    AVG(cpa.BodyLength) as AvgBodyLength,
    SUM(cpa.ViewCount) as TotalViews,
    MAX(cpa.AvgBounty) as MaxBounty,
    STRING_AGG(DISTINCT tp.TagName, ', ') FILTER (WHERE tp.Count > 500) as PopularTags,
    CASE 
        WHEN uem.LocationRank <= 3 THEN 'Top in Location'
        WHEN uem.BadgeRank <= 100 THEN 'Badge Leader'
        WHEN uem.Reputation > 10000 THEN 'High Rep'
        ELSE 'Regular User'
    END as UserTier,
    ROUND(AVG(cpa.DaysActive) FILTER (WHERE cpa.DaysActive > 0), 2) as AvgPostLifespanDays,
    (SELECT COUNT(*) FROM Votes v 
     WHERE v.UserId = uem.Id 
     AND v.VoteTypeId = 2 
     AND v.CreationDate > CURRENT_DATE - INTERVAL '365 days') as RecentUpvotes
FROM UserEngagementMetrics uem
INNER JOIN ComplexPostAnalysis cpa ON cpa.AuthorName = uem.DisplayName
LEFT OUTER JOIN Posts p2 ON p2.OwnerUserId = uem.Id AND p2.PostTypeId = 1
LEFT OUTER JOIN TagPopularity tp ON p2.Tags LIKE '%<' || tp.TagName || '>%' AND tp.AcceptanceRate > 50
WHERE uem.LocationRank <= 10
    AND cpa.EditCount < 20
    AND (cpa.AvgBounty > 0 OR cpa.PrimaryTagCategory IN (1, 2))
    AND NOT EXISTS (
        SELECT 1 
        FROM Votes v3 
        WHERE v3.UserId = uem.Id 
        AND v3.VoteTypeId = 12
        HAVING COUNT(*) > 5
    )
GROUP BY uem.Id, uem.DisplayName, uem.Location, uem.Reputation, uem.PostCount, 
         uem.BadgeCount, uem.QuestionScore, uem.AnswerScore, uem.LocationRank, 
         uem.BadgeRank, cpa.PostStatus
HAVING COUNT(DISTINCT cpa.PostId) >= 2
    AND SUM(cpa.ViewCount) > 1000
ORDER BY TotalScore DESC, uem.Reputation DESC, AvgBodyLength DESC
LIMIT 500;
