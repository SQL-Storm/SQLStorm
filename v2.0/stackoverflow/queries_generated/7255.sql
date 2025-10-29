-- {"query": "7255.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2512} 
WITH UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            ELSE 'Beginner'
        END as ReputationTier,
        ROW_NUMBER() OVER (PARTITION BY u.Reputation ORDER BY u.Id) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostEngagement AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        DATEDIFF(day, p.CreationDate, GETDATE()) as AgeInDays,
        CASE 
            WHEN p.Score > 100 THEN 'Popular'
            WHEN p.Score > 10 THEN 'Moderate'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Unpopular'
        END as Popularity,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPostsByUser,
        CASE 
            WHEN p.AnswerCount > 0 THEN (p.Score * 1.0 / (p.AnswerCount + 1))
            ELSE 0
        END as ScorePerAnswer
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityRank,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRankOverall
    FROM Tags t
    WHERE t.Count > 0
),
BadgesAndRewards AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.Date as BadgeDate,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class) as ClassBadgeCount,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            ELSE 'Bronze'
        END as BadgeType,
        DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date) as BadgeSequence,
        LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date) as PreviousBadgeDate,
        DATEDIFF(day, LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date), b.Date) as DaysBetweenBadges
    FROM Badges b
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Views,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.Badges,
    ua.ReputationTier,
    ua.ReputationRank,
    pe.PostId,
    pe.Title,
    pe.Score,
    pe.ViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.Popularity,
    pe.ScorePerAnswer,
    ta.TagName,
    ta.TagCount,
    ta.PopularityRank,
    bar.BadgeName,
    bar.BadgeType,
    bar.BadgeDate,
    bar.ClassBadgeCount,
    bar.BadgeSequence,
    CASE 
        WHEN ua.Reputation > 10000 AND ua.Badges > 50 THEN 'Elite Contributor'
        WHEN ua.Reputation > 5000 AND ua.TotalPosts > 100 THEN 'Veteran Contributor'
        WHEN ua.Reputation > 1000 AND ua.Questions > 20 THEN 'Active Contributor'
        ELSE 'Regular Contributor'
    END as ContributionLevel,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Score > 1000) THEN 'Highly Active'
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Score > 100) THEN 'Active'
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Score > 10) THEN 'Moderate'
        ELSE 'Inactive'
    END as ActivityLevel,
    COALESCE(ua.TotalPosts, 0) - COALESCE(ua.Questions, 0) - COALESCE(ua.Answers, 0) as OtherPosts,
    CASE 
        WHEN ua.Reputation = 0 THEN 'No Reputation Yet'
        WHEN ua.Reputation < 100 THEN 'New User'
        WHEN ua.Reputation < 1000 THEN 'Established User'
        WHEN ua.Reputation < 10000 THEN 'Experienced User'
        ELSE 'Veteran User'
    END as UserStatus,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 'Question Poster'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 THEN 'Answerer'
        ELSE 'Inactive'
    END as ContributionRole,
    CASE 
        WHEN MAX(pe.Score) > 1000 THEN 'Superstar'
        WHEN MAX(pe.Score) > 100 THEN 'Star'
        WHEN MAX(pe.Score) > 10 THEN 'Regular'
        ELSE 'Beginner'
    END as ContributionRank,
    CASE 
        WHEN MAX(pe.AgeInDays) < 30 THEN 'New'
        WHEN MAX(pe.AgeInDays) < 180 THEN 'Recent'
        WHEN MAX(pe.AgeInDays) < 365 THEN 'Stable'
        ELSE 'Veteran'
    END as PostAgeCategory,
    CASE 
        WHEN MAX(pe.ViewCount) > 10000 THEN 'Viral'
        WHEN MAX(pe.ViewCount) > 1000 THEN 'Popular'
        WHEN MAX(pe.ViewCount) > 100 THEN 'Moderate'
        ELSE 'Low'
    END as ViewCategory,
    ISNULL(ua.LastPostDate, ua.CreationDate) as RecentActivity,
    CASE 
        WHEN ua.Reputation > 0 THEN 
            ROUND((ua.Views * 1.0 / NULLIF(ua.Reputation, 0)), 2)
        ELSE 0 
    END as ViewsPerReputation,
    CASE 
        WHEN ua.AccountAgeDays > 0 THEN 
            ROUND((ua.TotalPosts * 1.0 / NULLIF(ua.AccountAgeDays, 0)), 3)
        ELSE 0 
    END as PostsPerDay,
    COALESCE(pe.Score, 0) - COALESCE(pe.PreviousScore, 0) as ScoreChange,
    CASE 
        WHEN MAX(pe.Score) > 100 AND MAX(pe.ViewCount) > 100 THEN 'High Impact'
        WHEN MAX(pe.Score) > 10 AND MAX(pe.ViewCount) > 10 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END as ImpactLevel,
    DATEDIFF(day, ua.LastPostDate, GETDATE()) as DaysSinceLastPost,
    DATEDIFF(day, ua.LastCommentDate, GETDATE()) as DaysSinceLastComment,
    NULLIF(u.Views, 0) as NormalizedViews,
    NULLIF(u.UpVotes, 0) as NormalizedUpVotes,
    NULLIF(u.DownVotes, 0) as NormalizedDownVotes

FROM Users u
LEFT JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN PostEngagement pe ON u.Id = pe.OwnerUserId
LEFT JOIN Tags ta ON EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = u.Id AND p.Tags LIKE '%' + ta.TagName + '%'
)
LEFT JOIN BadgesAndRewards bar ON u.Id = bar.UserId
INNER JOIN Posts p ON u.Id = p.OwnerUserId
WHERE u.Id > 0
  AND EXISTS (
    SELECT 1 FROM Posts p2 
    WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId IN (1, 2)
  )
  AND (
    (ua.ReputationTier IN ('Elite', 'Veteran') AND ua.Badges > 20)
    OR 
    (ua.ReputationTier = 'Advanced' AND ua.TotalPosts > 50)
  )
  AND (pe.Score > 10 OR pe.Score IS NULL)
  AND (ta.TagCount > 5 OR ta.TagCount IS NULL)
  AND pe.CreationDate > DATEADD(year, -2, GETDATE())
  AND (
    bar.BadgeDate > DATEADD(month, -6, GETDATE()) 
    OR bar.BadgeDate IS NULL
  )

GROUP BY 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Views,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.Badges,
    ua.ReputationTier,
    ua.ReputationRank,
    pe.PostId,
    pe.Title,
    pe.Score,
    pe.ViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.Popularity,
    pe.ScorePerAnswer,
    ta.TagName,
    ta.TagCount,
    ta.PopularityRank,
    bar.BadgeName,
    bar.BadgeType,
    bar.BadgeDate,
    bar.ClassBadgeCount,
    bar.BadgeSequence,
    ua.LastPostDate,
    ua.LastCommentDate,
    ua.CreationDate,
    ua.AccountAgeDays,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    pe.PreviousScore,
    MAX(pe.Score),
    MAX(pe.ViewCount),
    MAX(pe.AgeInDays)

HAVING 
    COUNT(*) > 1
    OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
    OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0

ORDER BY 
    ua.Reputation DESC,
    ua.Badges DESC,
    ua.TotalPosts DESC,
    ua.Comments DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;