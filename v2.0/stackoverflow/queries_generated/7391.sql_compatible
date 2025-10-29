WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_viewcount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.ViewCount) as MaxViews,
        STRING_AGG(DISTINCT p.Tags, '; ') as AllTags,
        COUNT(DISTINCT b.Id) as BadgesCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
        MIN(p.CreationDate) as FirstPostDate,
        MAX(p.CreationDate) as LastPostDate,
        EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 86400.0 as DaysActive
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
PostMetrics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score > 10 THEN 'Highly Voted'
            WHEN p.Score > 5 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Slightly Voted'
            ELSE 'No Votes'
        END as VotingLevel,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High Traffic'
            WHEN p.ViewCount > 100 THEN 'Moderate Traffic'
            WHEN p.ViewCount > 10 THEN 'Low Traffic'
            ELSE 'Very Low Traffic'
        END as TrafficLevel,
        CASE 
            WHEN p.AnswerCount > 5 THEN 'Well Answered'
            WHEN p.AnswerCount > 0 THEN 'Partially Answered'
            ELSE 'Unanswered'
        END as AnswerStatus,
        (p.Tags IS NOT NULL AND p.Tags != '' AND p.Tags != ' ') AS HasTags,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN 'Answer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Other'
        END as PostClass
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ComplexAnalysis AS (
    SELECT 
        pa.UserId,
        pa.DisplayName,
        pa.Reputation,
        pa.TotalPosts,
        pa.Questions,
        pa.Answers,
        pa.TotalScore,
        pa.AvgScore,
        pa.MaxViews,
        pa.AllTags,
        pa.BadgesCount,
        pa.GoldBadges,
        pa.SilverBadges,
        pa.BronzeBadges,
        pa.FirstPostDate,
        pa.LastPostDate,
        pa.DaysActive,
        CASE 
            WHEN pa.TotalPosts > 0 THEN 
                (CAST(pa.BadgesCount AS DOUBLE PRECISION) / CAST(pa.TotalPosts AS DOUBLE PRECISION)) * 100
            ELSE 0 
        END as BadgePerPostRatio,
        CASE 
            WHEN pa.TotalScore > 0 THEN 
                (CAST(pa.TotalPosts AS DOUBLE PRECISION) / CAST(pa.TotalScore AS DOUBLE PRECISION)) * 100
            ELSE 0 
        END as PostPerScoreRatio,
        CASE 
            WHEN pa.TotalScore > 0 THEN 
                (CAST(pa.AvgScore AS DOUBLE PRECISION) / CAST(pa.TotalScore AS DOUBLE PRECISION))
            ELSE 0 
        END as AvgScoreToTotalRatio,
        CASE 
            WHEN pa.MaxViews > 0 THEN 
                (CAST(pa.TotalPosts AS DOUBLE PRECISION) / CAST(pa.MaxViews AS DOUBLE PRECISION)) * 100
            ELSE 0 
        END as PostPerMaxViewRatio,
        CASE 
            WHEN pa.DaysActive > 0 THEN 
                (CAST(pa.TotalPosts AS DOUBLE PRECISION) / CAST(pa.DaysActive AS DOUBLE PRECISION))
            ELSE 0 
        END as DailyActivityRate,
        CASE 
            WHEN pa.GoldBadges IS NOT NULL AND pa.SilverBadges IS NOT NULL AND pa.BronzeBadges IS NOT NULL THEN
                (CAST(pa.GoldBadges AS DOUBLE PRECISION) + (CAST(pa.SilverBadges AS DOUBLE PRECISION) * 0.5) + (CAST(pa.BronzeBadges AS DOUBLE PRECISION) * 0.25)) / 
                (CAST(pa.TotalPosts AS DOUBLE PRECISION) + 1)
            ELSE 0 
        END as RewardEfficiency,
        CASE 
            WHEN pa.FirstPostDate IS NOT NULL AND pa.LastPostDate IS NOT NULL THEN
                EXTRACT(EPOCH FROM (pa.LastPostDate - pa.FirstPostDate)) / 86400.0
            ELSE NULL 
        END as TotalActivityDays,
        CASE 
            WHEN pa.Reputation > 10000 THEN 'Elite'
            WHEN pa.Reputation > 5000 THEN 'Advanced'
            WHEN pa.Reputation > 1000 THEN 'Experienced'
            WHEN pa.Reputation > 500 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserTier
    FROM UserActivityStats pa
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.TotalScore,
    ca.AvgScore,
    ca.MaxViews,
    ca.AllTags,
    ca.BadgesCount,
    ca.GoldBadges,
    ca.SilverBadges,
    ca.BronzeBadges,
    ca.FirstPostDate,
    ca.LastPostDate,
    ca.DaysActive,
    ca.BadgePerPostRatio,
    ca.PostPerScoreRatio,
    ca.AvgScoreToTotalRatio,
    ca.PostPerMaxViewRatio,
    ca.DailyActivityRate,
    ca.RewardEfficiency,
    ca.TotalActivityDays,
    ca.UserTier,
    CASE 
        WHEN ca.BadgesCount > 50 AND ca.Reputation > 10000 THEN 'Top Performer'
        WHEN ca.BadgesCount > 25 AND ca.Reputation > 5000 THEN 'Active Contributor'
        WHEN ca.BadgesCount > 10 AND ca.Reputation > 1000 THEN 'Regular Member'
        ELSE 'Standard User'
    END as RecognitionLevel,
    STRING_AGG(DISTINCT (pm.PostType || ': ' || COALESCE(pm.Title, '')), ' | ') as RecentActivity,
    STRING_AGG(DISTINCT CASE 
        WHEN pm.Score > 10 THEN pm.Title || ' (' || CAST(pm.Score AS VARCHAR(10)) || ')'
        ELSE NULL
    END, ' | ') as HighScoringPosts,
    COUNT(DISTINCT CASE 
        WHEN pm.AnswerStatus = 'Well Answered' THEN pm.Id 
        ELSE NULL 
    END) as WellAnsweredQuestions,
    COUNT(DISTINCT CASE 
        WHEN pm.TrafficLevel IN ('High Traffic', 'Moderate Traffic') THEN pm.Id 
        ELSE NULL 
    END) as PopularPosts,
    COUNT(DISTINCT CASE 
        WHEN pm.VotingLevel IN ('Highly Voted', 'Moderately Voted') THEN pm.Id 
        ELSE NULL 
    END) as WellRatedPosts,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id 
         WHERE p.OwnerUserId = ca.UserId AND v.VoteTypeId IN (2, 3)), 
        0
    ) as VoteActivityCount,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c 
         WHERE c.UserId = ca.UserId), 
        0
    ) as CommentActivityCount,
    CASE 
        WHEN ca.Reputation > 5000 THEN 
            'This user has demonstrated significant expertise and contribution to the community.'
        WHEN ca.Reputation > 1000 THEN 
            'This user is actively participating in the community.'
        ELSE 
            'This user is still building their contribution level.'
    END as CommunityAssessment,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p 
            WHERE p.OwnerUserId = ca.UserId 
            AND p.PostTypeId = 1 
            AND p.Score > 100) 
        THEN 'High Impact Question Author'
        ELSE 'Regular Contributor'
    END as ContributionType,
    CASE 
        WHEN ca.TotalPosts > 100 AND ca.AvgScore > 10 
        THEN 'High Performance Contributor'
        WHEN ca.TotalPosts > 50 AND ca.AvgScore > 5 
        THEN 'Consistent Contributor'
        WHEN ca.TotalPosts > 10 AND ca.AvgScore > 0 
        THEN 'Emerging Contributor'
        ELSE 'New Contributor'
    END as PerformanceTier
FROM ComplexAnalysis ca
LEFT JOIN PostMetrics pm ON ca.UserId = pm.OwnerUserId
WHERE ca.TotalPosts > 0
GROUP BY 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.TotalScore,
    ca.AvgScore,
    ca.MaxViews,
    ca.AllTags,
    ca.BadgesCount,
    ca.GoldBadges,
    ca.SilverBadges,
    ca.BronzeBadges,
    ca.FirstPostDate,
    ca.LastPostDate,
    ca.DaysActive,
    ca.BadgePerPostRatio,
    ca.PostPerScoreRatio,
    ca.AvgScoreToTotalRatio,
    ca.PostPerMaxViewRatio,
    ca.DailyActivityRate,
    ca.RewardEfficiency,
    ca.TotalActivityDays,
    ca.UserTier
HAVING 
    MIN(CASE WHEN pm.PostClass = 'Answer' THEN 1 ELSE 0 END) = 1
    OR MIN(CASE WHEN pm.PostClass = 'Question' THEN 1 ELSE 0 END) = 1
    OR MAX(pm.Score) IS NOT NULL
ORDER BY 
    ca.TotalScore DESC,
    ca.BadgesCount DESC,
    ca.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;