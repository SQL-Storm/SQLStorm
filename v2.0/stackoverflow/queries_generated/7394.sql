-- {"query": "7394.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1870} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Expert'
            WHEN u.Reputation > 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationTier,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RepRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END as IsAnswered,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserRank,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalRank,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreQuartile
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score > 100 
    AND p.PostTypeId IN (1,2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        AVG(t.Count) OVER () as AvgTagCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
UserPostActivity AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        CASE 
            WHEN ua.PostCount > 100 THEN 'Highly Active'
            WHEN ua.PostCount > 50 THEN 'Active'
            WHEN ua.PostCount > 10 THEN 'Moderate'
            ELSE 'Low'
        END as ActivityLevel,
        CASE 
            WHEN ua.LastPostDate > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 1
            ELSE 0
        END as RecentActivity,
        COALESCE(ua.TotalScore, 0) as TotalScore,
        COALESCE(ua.TotalViews, 0) as TotalViews
    FROM UserActivityStats ua
),
ComplexPostAnalysis AS (
    SELECT 
        tp.Id,
        tp.Title,
        tp.Body,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.OwnerName,
        tp.PostType,
        tp.IsAnswered,
        tp.GlobalRank,
        tp.ScoreQuartile,
        CASE 
            WHEN tp.Score > 500 THEN 'Very High'
            WHEN tp.Score > 100 THEN 'High'
            WHEN tp.Score > 50 THEN 'Medium'
            WHEN tp.Score > 10 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreLevel,
        LENGTH(tp.Body) as BodyLength,
        CASE 
            WHEN LENGTH(tp.Body) > 1000 THEN 'Long'
            WHEN LENGTH(tp.Body) > 500 THEN 'Medium'
            ELSE 'Short'
        END as PostLength,
        SUBSTRING(tp.Body FROM 1 FOR 100) as BodyPreview
    FROM TopPosts tp
),
CombinedResults AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.PostCount,
        upa.CommentCount,
        upa.BadgeCount,
        upa.ActivityLevel,
        upa.RecentActivity,
        upa.TotalScore,
        cp.Title as TopPostTitle,
        cp.Score as TopPostScore,
        cp.ViewCount as TopPostViews,
        cp.CreationDate as TopPostDate,
        cp.ScoreLevel,
        cp.PostLength,
        ta.TagName,
        ta.Count as TagCount,
        ta.PopularityLevel,
        (upa.Reputation + upa.PostCount + upa.CommentCount + upa.BadgeCount) as CompositeScore,
        CASE 
            WHEN (upa.Reputation + upa.PostCount + upa.CommentCount + upa.BadgeCount) > 1000 THEN 'Top Contributor'
            WHEN (upa.Reputation + upa.PostCount + upa.CommentCount + upa.BadgeCount) > 500 THEN 'Good Contributor'
            ELSE 'Regular Contributor'
        END as ContributionLevel
    FROM UserPostActivity upa
    LEFT JOIN ComplexPostAnalysis cp ON upa.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = cp.Id)
    LEFT JOIN TagAnalysis ta ON ta.PopularityRank = 1
    WHERE upa.Reputation > 1000
)
SELECT 
    cr.UserId,
    cr.DisplayName,
    cr.Reputation,
    cr.PostCount,
    cr.CommentCount,
    cr.BadgeCount,
    cr.ActivityLevel,
    cr.RecentActivity,
    cr.TotalScore,
    cr.TopPostTitle,
    cr.TopPostScore,
    cr.TopPostViews,
    cr.TopPostDate,
    cr.ScoreLevel,
    cr.PostLength,
    cr.TagName,
    cr.TagCount,
    cr.PopularityLevel,
    cr.CompositeScore,
    cr.ContributionLevel,
    RANK() OVER (ORDER BY cr.CompositeScore DESC) as OverallRank,
    DENSE_RANK() OVER (ORDER BY cr.Reputation DESC) as ReputationRank,
    COUNT(*) OVER () as TotalContributors,
    CASE 
        WHEN cr.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
        WHEN cr.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
        ELSE 'Average'
    END as ReputationComparison,
    CONCAT('User_', cr.UserId, '_', cr.DisplayName) as UserIdentifier,
    COALESCE(cr.TopPostViews, 0) + COALESCE(cr.TotalScore, 0) as CombinedMetric,
    CASE 
        WHEN cr.Reputation > 10000 AND cr.PostCount > 100 THEN 'Elite Contributor'
        WHEN cr.Reputation > 5000 AND cr.PostCount > 50 THEN 'Veteran Contributor'
        WHEN cr.Reputation > 1000 AND cr.PostCount > 10 THEN 'Experienced Contributor'
        ELSE 'Regular Contributor'
    END as ContributorTier,
    ROW_NUMBER() OVER (ORDER BY cr.ScoreLevel DESC, cr.PostCount DESC, cr.Reputation DESC) as DetailedRanking,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = cr.UserId AND PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = cr.UserId AND PostTypeId = 2) as AnswerCount,
    COALESCE((SELECT AVG(Score) FROM Posts WHERE OwnerUserId = cr.UserId), 0) as AvgPostScore,
    COALESCE((SELECT AVG(ViewCount) FROM Posts WHERE OwnerUserId = cr.UserId), 0) as AvgPostViews
FROM CombinedResults cr
WHERE cr.Reputation > 5000
AND (cr.PostCount > 50 OR cr.BadgeCount > 5)
AND cr.ActivityLevel IN ('Highly Active', 'Active')
AND cr.RecentActivity = 1
ORDER BY cr.CompositeScore DESC, cr.Reputation DESC, cr.PostCount DESC
LIMIT 100;