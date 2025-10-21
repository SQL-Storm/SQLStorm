-- {"query": "16012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 30355, "output_tokens": 28402} 

WITH RECURSIVE UserEngagementMetrics AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) as NetVotes,
        EXTRACT(YEAR FROM u.CreationDate) as JoinYear,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserTier
    FROM Users u
    WHERE u.Reputation > 50 AND u.LastAccessDate > CURRENT_DATE - INTERVAL '2 years'
),
PostPerformance AS (
    SELECT 
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) as PostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as RollingAvgScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevPostDate,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostScore,
        STRING_AGG(DISTINCT COALESCE(SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN SUBSTRING(p.Tags FROM 2)) - 1), 'no-tag'), '|') 
            OVER (PARTITION BY p.OwnerUserId) as UserTopTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate > CURRENT_DATE - INTERVAL '5 years'
        AND p.Score IS NOT NULL
),
BadgeAchievements AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as BronzeBadges,
        MAX(CASE WHEN b.TagBased = 1 THEN b.Name ELSE NULL END) as TopTagBadge,
        COUNT(DISTINCT EXTRACT(MONTH FROM b.Date)) as MonthsWithBadges
    FROM Badges b
    WHERE b.Date > CURRENT_DATE - INTERVAL '3 years'
    GROUP BY b.UserId
    HAVING COUNT(*) >= 5
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVoteCount,
        SUM(COALESCE(v.BountyAmount, 0)) as TotalBounty,
        MAX(v.CreationDate) as LastVoteDate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.CreationDate) as MedianVoteDate
    FROM Votes v
    WHERE v.VoteTypeId IN (1, 2, 3, 8, 9)
        AND v.CreationDate > CURRENT_DATE - INTERVAL '4 years'
    GROUP BY v.PostId
),
CommentActivity AS (
    SELECT 
        c.PostId,
        c.UserId as CommenterId,
        AVG(LENGTH(c.Text)) as AvgCommentLength,
        COUNT(*) as CommentFrequency,
        MAX(c.Score) as BestCommentScore
    FROM Comments c
    WHERE c.CreationDate > CURRENT_DATE - INTERVAL '3 years'
        AND c.UserId IS NOT NULL
    GROUP BY c.PostId, c.UserId
)
SELECT DISTINCT
    uem.DisplayName,
    uem.UserTier,
    uem.Reputation,
    COALESCE(ba.GoldBadges, 0) + COALESCE(ba.SilverBadges, 0) * 0.5 + COALESCE(ba.BronzeBadges, 0) * 0.25 as WeightedBadgeScore,
    pp.PostId,
    pp.Score as PostScore,
    pp.PostRank,
    ROUND(pp.RollingAvgScore::numeric, 2) as RollingAvgScore,
    COALESCE(va.UpVoteCount, 0)::float / NULLIF(COALESCE(va.DownVoteCount, 1), 0) as VoteRatio,
    CASE 
        WHEN pp.PrevPostDate IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (p.CreationDate - pp.PrevPostDate)) / 86400.0
        ELSE NULL 
    END as DaysSincePrevPost,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.PostId = pp.PostId AND pl.LinkTypeId = 1), 0
    ) as LinkedPostCount,
    (SELECT COUNT(DISTINCT ph.UserId)
     FROM PostHistory ph
     WHERE ph.PostId = pp.PostId 
         AND ph.PostHistoryTypeId IN (4, 5, 6)
         AND ph.UserId != pp.OwnerUserId
    ) as UniqueEditors,
    COALESCE(ca.AvgCommentLength, 0) as AvgCommentLength,
    SUBSTRING(COALESCE(p.Title, 'No Title') FROM 1 FOR 50) || 
        CASE WHEN LENGTH(COALESCE(p.Title, '')) > 50 THEN '...' ELSE '' END as TruncatedTitle,
    CASE 
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        WHEN p.AnswerCount > 0 THEN 'Has Answers'
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END as PostStatus,
    COALESCE(va.TotalBounty, 0) as TotalBountyValue,
    ROW_NUMBER() OVER (
        PARTITION BY uem.UserTier 
        ORDER BY pp.Score * LOG(NULLIF(pp.ViewCount, 0) + 1) DESC NULLS LAST
    ) as TierRank
FROM UserEngagementMetrics uem
INNER JOIN PostPerformance pp ON uem.UserId = pp.OwnerUserId
LEFT OUTER JOIN Posts p ON pp.PostId = p.Id
LEFT OUTER JOIN BadgeAchievements ba ON uem.UserId = ba.UserId
LEFT OUTER JOIN VoteAnalysis va ON pp.PostId = va.PostId
LEFT OUTER JOIN CommentActivity ca ON pp.PostId = ca.PostId AND uem.UserId = ca.CommenterId
WHERE pp.PostRank <= 10
    AND (pp.Score >= 5 OR pp.ViewCount > 1000)
    AND (ba.GoldBadges > 0 OR ba.SilverBadges > 2 OR uem.Reputation > 500)
    AND NOT EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.PostId = pp.PostId 
            AND v.VoteTypeId IN (4, 12) 
            AND v.CreationDate > p.CreationDate + INTERVAL '30 days'
    )
ORDER BY 
    CASE uem.UserTier
        WHEN 'Elite' THEN 1
        WHEN 'Advanced' THEN 2
        WHEN 'Intermediate' THEN 3
        ELSE 4
    END,
    WeightedBadgeScore DESC,
    pp.Score DESC,
    TierRank
LIMIT 1000;
