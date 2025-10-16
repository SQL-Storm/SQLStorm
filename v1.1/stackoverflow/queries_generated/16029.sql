-- {"query": "16029.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 70050, "output_tokens": 65870} 

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        AVG(CASE WHEN p.ViewCount IS NOT NULL AND p.ViewCount > 0 THEN p.ViewCount ELSE NULL END) AS AvgViewCount,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(SUBSTRING(u.Location FROM 1 FOR 20), 'Unknown') ORDER BY u.Reputation DESC) AS LocationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeCountRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT OUTER JOIN Comments c ON u.Id = c.UserId
    LEFT OUTER JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2015-01-01'
        AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT c.Id) > 10
),
PostPerformanceAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        STRING_AGG(DISTINCT SUBSTRING(COALESCE(t.TagName, 'untagged'), 1, 15), ', ') AS TopTags,
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS OutboundLinks,
        (SELECT COUNT(*) 
         FROM PostLinks pl2 
         WHERE pl2.RelatedPostId = p.Id AND pl2.LinkTypeId = 3) AS DuplicateCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Unanswered'
        END AS PostStatus,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) - p.CreationDate AS TimeToNextPost,
        NTILE(10) OVER (ORDER BY COALESCE(p.ViewCount, 0) DESC) AS ViewDecile
    FROM Posts p
    LEFT OUTER JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag
    ) AS extracted_tags ON TRUE
    LEFT OUTER JOIN Tags t ON extracted_tags.tag = t.TagName
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= '2018-01-01'
        AND (p.Body IS NOT NULL AND LENGTH(p.Body) > 100)
    GROUP BY p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.OwnerUserId, 
             p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, 
             p.AcceptedAnswerId, p.CreationDate
),
BadgeActivityCorrelation AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ' | ') AS GoldBadgeNames
    FROM Badges b
    WHERE b.Date >= '2016-01-01'
    GROUP BY b.UserId
)
SELECT 
    uem.DisplayName,
    COALESCE(NULLIF(TRIM(uem.Location), ''), 'Location Not Specified') AS UserLocation,
    uem.Reputation,
    uem.PostCount,
    uem.CommentCount,
    uem.LocationRank,
    ROUND(uem.AvgViewCount::numeric, 2) AS AvgViews,
    COALESCE(bac.GoldBadges, 0) + COALESCE(bac.SilverBadges, 0) * 0.5 + COALESCE(bac.BronzeBadges, 0) * 0.25 AS WeightedBadgeScore,
    ppa_stats.AvgPostScore,
    ppa_stats.MaxViewCount,
    ppa_stats.TotalOutboundLinks,
    ppa_stats.ClosedPostRatio,
    CASE 
        WHEN uem.Reputation > 50000 THEN 'Elite'
        WHEN uem.Reputation > 10000 THEN 'Expert'
        WHEN uem.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    COALESCE(bac.GoldBadgeNames, 'None') AS TopAchievements,
    (SELECT COUNT(*) 
     FROM Comments c2 
     WHERE c2.UserId = uem.UserId 
       AND c2.Score > 5 
       AND c2.CreationDate >= CURRENT_DATE - INTERVAL '2 years') AS HighScoredRecentComments,
    EXISTS(
        SELECT 1 
        FROM Posts p_sub 
        WHERE p_sub.OwnerUserId = uem.UserId 
          AND p_sub.AcceptedAnswerId IS NOT NULL 
          AND p_sub.Score > 50
    ) AS HasHighlyAcceptedQuestions
FROM UserEngagementMetrics uem
LEFT OUTER JOIN BadgeActivityCorrelation bac ON uem.UserId = bac.UserId
LEFT OUTER JOIN LATERAL (
    SELECT 
        AVG(ppa.Score) AS AvgPostScore,
        MAX(ppa.ViewCount) AS MaxViewCount,
        SUM(ppa.OutboundLinks) AS TotalOutboundLinks,
        CASE 
            WHEN COUNT(*) > 0 THEN ROUND(COUNT(CASE WHEN ppa.PostStatus = 'Closed' THEN 1 END)::numeric / COUNT(*)::numeric, 3)
            ELSE 0 
        END AS ClosedPostRatio
    FROM PostPerformanceAnalysis ppa
    WHERE ppa.OwnerUserId = uem.UserId
) AS ppa_stats ON TRUE
WHERE uem.Reputation > 100
    AND uem.PostCount >= 3
    AND (bac.GoldBadges IS NOT NULL OR bac.SilverBadges >= 2 OR uem.QuestionScore + uem.AnswerScore > 100)
    AND uem.LocationRank <= 50
ORDER BY 
    WeightedBadgeScore DESC NULLS LAST,
    uem.Reputation DESC,
    ppa_stats.AvgPostScore DESC NULLS LAST
LIMIT 500;
