-- {"query": "7042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2398} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS ReputationRank,
        CASE 
            WHEN u.Views > 10000 THEN 'Elite'
            WHEN u.Views > 1000 THEN 'Advanced'
            WHEN u.Views > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserLevel,
        ABS(COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0)) AS VoteDifference,
        CASE 
            WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN 1 
            ELSE 0 
        END AS HasWebsite,
        CASE 
            WHEN u.Location IS NOT NULL AND u.Location != '' THEN 1 
            ELSE 0 
        END AS HasLocation,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) AS AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.WebsiteUrl, u.Location, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        UserLevel,
        VoteDifference,
        HasWebsite,
        HasLocation,
        AccountAgeDays,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS GlobalRank,
        RANK() OVER (PARTITION BY UserLevel ORDER BY Reputation DESC) AS LevelRank
    FROM UserActivityStats
    WHERE PostCount > 0 OR CommentCount > 0 OR BadgeCount > 0
),
UserPostAnalytics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgScore,
        MAX(p.Score) AS MaxScore,
        MIN(p.Score) AS MinScore,
        COUNT(DISTINCT p.PostTypeId) AS PostTypeVariety,
        STRING_AGG(DISTINCT pt.Name, ', ') AS PostTypes,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS AcceptedAnswers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
        AVG(CAST(p.ViewCount AS FLOAT)) AS AvgViews,
        COUNT(DISTINCT CASE WHEN p.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL 30 DAY THEN 1 END) AS RecentActivityCount,
        COUNT(DISTINCT CASE WHEN p.Score > (SELECT AVG(Score) FROM Posts) THEN 1 END) AS AboveAveragePosts,
        MAX(p.CreationDate) AS LastActivity
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY p.OwnerUserId
),
PostComplexityMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountActual,
        CASE 
            WHEN p.Score > 0 AND p.Score < 5 THEN 'Low'
            WHEN p.Score >= 5 AND p.Score < 10 THEN 'Medium'
            WHEN p.Score >= 10 THEN 'High'
            ELSE 'None'
        END AS ScoreCategory,
        CASE 
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 1000 THEN 'Long'
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 500 THEN 'Medium'
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 100 THEN 'Short'
            ELSE 'VeryShort'
        END AS BodyLengthCategory,
        CASE 
            WHEN p.AnswerCount > 0 THEN 'Answered'
            WHEN p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL 7 DAY THEN 'New'
            ELSE 'Unanswered'
        END AS PostStatus,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS Favorites,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) AS NextScore,
        NTILE(4) OVER (ORDER BY p.Score) AS Quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
DetailedUserPerformance AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.UserLevel,
        tu.VoteDifference,
        tu.HasWebsite,
        tu.HasLocation,
        tu.AccountAgeDays,
        tu.GlobalRank,
        tu.LevelRank,
        COALESCE(upa.TotalPosts, 0) AS TotalPosts,
        COALESCE(upa.AvgScore, 0) AS AvgScore,
        COALESCE(upa.MaxScore, 0) AS MaxScore,
        COALESCE(upa.MinScore, 0) AS MinScore,
        COALESCE(upa.PostTypeVariety, 0) AS PostTypeVariety,
        upa.PostTypes,
        COALESCE(upa.AcceptedAnswers, 0) AS AcceptedAnswers,
        COALESCE(upa.Questions, 0) AS Questions,
        COALESCE(upa.Answers, 0) AS Answers,
        COALESCE(upa.AvgViews, 0) AS AvgViews,
        COALESCE(upa.RecentActivityCount, 0) AS RecentActivityCount,
        COALESCE(upa.AboveAveragePosts, 0) AS AboveAveragePosts,
        upa.LastActivity,
        CASE 
            WHEN upa.TotalPosts > 0 AND upa.AvgScore > 5 THEN 'HighlyActive'
            WHEN upa.TotalPosts > 0 THEN 'Active'
            ELSE 'Inactive'
        END AS ActivityStatus,
        CASE 
            WHEN upa.AvgScore > (SELECT AVG(Score) FROM Posts) THEN 'AboveAverage'
            ELSE 'BelowAverage'
        END AS PerformanceLevel
    FROM TopUsers tu
    LEFT JOIN UserPostAnalytics upa ON tu.UserId = upa.OwnerUserId
)
SELECT 
    dup.UserId,
    dup.DisplayName,
    dup.Reputation,
    dup.PostCount,
    dup.CommentCount,
    dup.BadgeCount,
    dup.UserLevel,
    dup.VoteDifference,
    dup.HasWebsite,
    dup.HasLocation,
    dup.AccountAgeDays,
    dup.GlobalRank,
    dup.LevelRank,
    dup.TotalPosts,
    ROUND(dup.AvgScore, 2) AS AvgScore,
    dup.MaxScore,
    dup.MinScore,
    dup.PostTypeVariety,
    dup.PostTypes,
    dup.AcceptedAnswers,
    dup.Questions,
    dup.Answers,
    ROUND(dup.AvgViews, 0) AS AvgViews,
    dup.RecentActivityCount,
    dup.AboveAveragePosts,
    dup.LastActivity,
    dup.ActivityStatus,
    dup.PerformanceLevel,
    (
        SELECT COUNT(*) 
        FROM PostComplexityMetrics pcm 
        WHERE pcm.OwnerUserId = dup.UserId 
        AND pcm.ScoreCategory IN ('High', 'Medium')
    ) AS HighMediumScorePosts,
    (
        SELECT COUNT(*) 
        FROM PostComplexityMetrics pcm 
        WHERE pcm.OwnerUserId = dup.UserId 
        AND pcm.BodyLengthCategory IN ('Long', 'Medium')
    ) AS LongMediumBodyPosts,
    (
        SELECT COUNT(*) 
        FROM PostComplexityMetrics pcm 
        WHERE pcm.OwnerUserId = dup.UserId 
        AND pcm.PostStatus = 'Answered'
    ) AS AnsweredPosts,
    (
        SELECT STRING_AGG(DISTINCT p.Title, '; ') 
        FROM Posts p 
        JOIN PostComplexityMetrics pcm ON p.Id = pcm.PostId 
        WHERE p.OwnerUserId = dup.UserId 
        AND pcm.GlobalScoreRank <= 5
        ORDER BY pcm.GlobalScoreRank
        FETCH FIRST 3 ROWS ONLY
    ) AS TopPosts,
    (SELECT STRING_AGG(DISTINCT pt.Name, ', ') 
     FROM Posts p 
     JOIN PostTypes pt ON p.PostTypeId = pt.Id 
     WHERE p.OwnerUserId = dup.UserId 
     GROUP BY p.OwnerUserId) AS OwnedPostTypes,
    -- Complex calculations with NULL handling
    CASE 
        WHEN dup.TotalPosts > 0 AND dup.AvgScore > 0 THEN 
            ROUND((dup.TotalPosts * dup.AvgScore) / (dup.Reputation + 1.0), 2)
        ELSE 0 
    END AS ScoreEfficiencyRatio,
    CASE 
        WHEN dup.PostCount > 0 AND dup.CommentCount > 0 THEN 
            ROUND((dup.CommentCount * 100.0) / dup.PostCount, 2)
        ELSE 0 
    END AS CommentPerPostRatio,
    CASE 
        WHEN dup.Reputation > 0 THEN 
            ROUND((dup.BadgeCount * 100.0) / dup.Reputation, 2)
        ELSE 0 
    END AS BadgeToRepRatio,
    -- Complex window function and ranking operations
    LAG(dup.Reputation) OVER (ORDER BY dup.Reputation DESC) AS PreviousReputation,
    LEAD(dup.Reputation) OVER (ORDER BY dup.Reputation ASC) AS NextReputation,
    ROW_NUMBER() OVER (ORDER BY dup.TotalPosts DESC) AS TopPostsRank,
    DENSE_RANK() OVER (ORDER BY dup.AvgScore DESC) AS TopAvgScoreRank,
    PERCENT_RANK() OVER (ORDER BY dup.Reputation) AS ReputationPercentile
FROM DetailedUserPerformance dup
WHERE dup.Reputation > 100 
  AND dup.PostCount > 0
HAVING COUNT(*) > 1
ORDER BY dup.Reputation DESC, dup.GlobalRank ASC
LIMIT 100;