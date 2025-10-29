-- {"query": "7287.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3890} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDesc,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) * 10 + COALESCE(p.CommentCount, 0) * 5 AS ActivityScore,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) AS DaysSinceCreation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS GlobalViewRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS CumulativeScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(SUM(ps.Score), 0) AS TotalScore,
        COALESCE(COUNT(ps.Id), 0) AS TotalPosts,
        COALESCE(AVG(ps.Score), 0) AS AvgScore,
        COALESCE(MAX(ps.ViewCount), 0) AS MaxViews,
        COALESCE(SUM(ps.ViewCount), 0) AS TotalViews,
        COALESCE(COUNT(DISTINCT ps.Tags), 0) AS UniqueTags,
        COALESCE(COUNT(DISTINCT ps.Title), 0) AS UniqueTitles,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Member'
            ELSE 'Newbie'
        END AS ReputationTier
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(t.Count, 0) * 100.0 / (SELECT SUM(Count) FROM Tags) AS PercentOfTotal,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Less Popular'
            ELSE 'Rare'
        END AS PopularityLevel,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            ELSE 'Standard'
        END AS TagType
    FROM Tags t
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.ActivityScore,
        ps.DaysSinceCreation,
        ps.UserPostRank,
        ps.GlobalScoreRank,
        ps.GlobalViewRank,
        ps.PrevScore,
        ps.NextScore,
        ps.AvgUserScore,
        ps.TotalUserPosts,
        ps.CumulativeScore,
        CASE 
            WHEN ps.PrevScore IS NOT NULL AND ps.Score > ps.PrevScore THEN 'Improving'
            WHEN ps.PrevScore IS NOT NULL AND ps.Score < ps.PrevScore THEN 'Declining'
            WHEN ps.PrevScore IS NOT NULL AND ps.Score = ps.PrevScore THEN 'Stable'
            ELSE 'New'
        END AS Trend,
        CASE 
            WHEN ps.CreationDate >= '2023-01-01' THEN 'Recent'
            WHEN ps.CreationDate >= '2022-01-01' THEN '2022'
            WHEN ps.CreationDate >= '2021-01-01' THEN '2021'
            ELSE 'Older'
        END AS PostYear,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 'Has Answers'
            WHEN ps.AnswerCount = 0 THEN 'No Answers'
            ELSE 'Unknown'
        END AS AnswerStatus,
        CASE 
            WHEN ps.CommentCount > 0 THEN 'Has Comments'
            WHEN ps.CommentCount = 0 THEN 'No Comments'
            ELSE 'Unknown'
        END AS CommentStatus,
        CASE 
            WHEN ps.ViewCount > 1000 THEN 'High Visibility'
            WHEN ps.ViewCount > 100 THEN 'Medium Visibility'
            WHEN ps.ViewCount > 0 THEN 'Low Visibility'
            ELSE 'No Views'
        END AS VisibilityLevel
    FROM PostStats ps
)
SELECT 
    COALESCE(ua.DisplayName, 'Anonymous') AS AuthorDisplayName,
    COALESCE(ua.ReputationTier, 'Unknown') AS ReputationTier,
    COALESCE(ua.TotalScore, 0) AS AuthorTotalScore,
    COALESCE(ua.TotalPosts, 0) AS AuthorTotalPosts,
    COALESCE(ua.AvgScore, 0) AS AuthorAvgScore,
    CASE 
        WHEN COUNT(cpa.Id) > 0 THEN 'Has Posts'
        ELSE 'No Posts'
    END AS HasPosts,
    COUNT(cpa.Id) AS PostCount,
    COALESCE(SUM(cpa.Score), 0) AS TotalPostScore,
    COALESCE(AVG(cpa.Score), 0) AS AvgPostScore,
    COALESCE(SUM(cpa.ViewCount), 0) AS TotalPostViews,
    COALESCE(MAX(cpa.ActivityScore), 0) AS MaxActivityScore,
    COALESCE(STRCAT('Tags: ', GROUP_CONCAT(DISTINCT SUBSTRING_INDEX(SUBSTRING_INDEX(cpa.Tags, '<', numbers.n), '<', -1) SEPARATOR ', ')), 'None') AS TagList,
    COALESCE(COUNT(DISTINCT cpa.Title), 0) AS DistinctTitles,
    COALESCE(AVG(cpa.DaysSinceCreation), 0) AS AvgDaysSinceCreation,
    COALESCE(SUM(CASE WHEN cpa.Trend = 'Improving' THEN 1 ELSE 0 END), 0) AS ImprovingPosts,
    COALESCE(SUM(CASE WHEN cpa.Trend = 'Declining' THEN 1 ELSE 0 END), 0) AS DecliningPosts,
    COALESCE(SUM(CASE WHEN cpa.Trend = 'Stable' THEN 1 ELSE 0 END), 0) AS StablePosts,
    COALESCE(SUM(CASE WHEN cpa.VisibilityLevel = 'High Visibility' THEN 1 ELSE 0 END), 0) AS HighVisibilityPosts,
    COALESCE(SUM(CASE WHEN cpa.VisibilityLevel = 'Medium Visibility' THEN 1 ELSE 0 END), 0) AS MediumVisibilityPosts,
    COALESCE(SUM(CASE WHEN cpa.VisibilityLevel = 'Low Visibility' THEN 1 ELSE 0 END), 0) AS LowVisibilityPosts,
    COALESCE(SUM(CASE WHEN cpa.PostYear = 'Recent' THEN 1 ELSE 0 END), 0) AS RecentPosts,
    COALESCE(SUM(CASE WHEN cpa.PostYear = '2022' THEN 1 ELSE 0 END), 0) AS Posts2022,
    COALESCE(SUM(CASE WHEN cpa.PostYear = '2021' THEN 1 ELSE 0 END), 0) AS Posts2021,
    COALESCE(SUM(CASE WHEN cpa.AnswerStatus = 'Has Answers' THEN 1 ELSE 0 END), 0) AS PostsWithAnswers,
    COALESCE(SUM(CASE WHEN cpa.AnswerStatus = 'No Answers' THEN 1 ELSE 0 END), 0) AS PostsWithoutAnswers,
    COALESCE(SUM(CASE WHEN cpa.CommentStatus = 'Has Comments' THEN 1 ELSE 0 END), 0) AS PostsWithComments,
    COALESCE(SUM(CASE WHEN cpa.CommentStatus = 'No Comments' THEN 1 ELSE 0 END), 0) AS PostsWithoutComments,
    COALESCE(SUM(CASE WHEN cpa.GlobalScoreRank <= 10 THEN 1 ELSE 0 END), 0) AS Top10RankedPosts,
    COALESCE(SUM(CASE WHEN cpa.GlobalViewRank <= 50 THEN 1 ELSE 0 END), 0) AS Top50ViewedPosts,
    COALESCE(SUM(CASE WHEN cpa.CumulativeScore >= 100 THEN 1 ELSE 0 END), 0) AS HighCumulativeScorePosts
FROM UserStats ua
LEFT JOIN ComplexPostAnalysis cpa ON ua.UserId = cpa.OwnerUserId
LEFT JOIN (
    SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
    UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
) numbers ON CHAR_LENGTH(cpa.Tags) - CHAR_LENGTH(REPLACE(cpa.Tags, '<', '')) >= numbers.n - 1
WHERE ua.UserId IS NOT NULL
GROUP BY ua.UserId, ua.DisplayName, ua.ReputationTier, ua.TotalScore, ua.TotalPosts, ua.AvgScore
HAVING COUNT(cpa.Id) > 0
UNION ALL
SELECT 
    'Overall Statistics' AS AuthorDisplayName,
    'Total' AS ReputationTier,
    SUM(ua.TotalScore) AS AuthorTotalScore,
    SUM(ua.TotalPosts) AS AuthorTotalPosts,
    AVG(ua.AvgScore) AS AuthorAvgScore,
    'All Users' AS HasPosts,
    COUNT(DISTINCT cpa.Id) AS PostCount,
    SUM(cpa.Score) AS TotalPostScore,
    AVG(cpa.Score) AS AvgPostScore,
    SUM(cpa.ViewCount) AS TotalPostViews,
    MAX(cpa.ActivityScore) AS MaxActivityScore,
    'Summary' AS TagList,
    COUNT(DISTINCT cpa.Title) AS DistinctTitles,
    AVG(cpa.DaysSinceCreation) AS AvgDaysSinceCreation,
    SUM(CASE WHEN cpa.Trend = 'Improving' THEN 1 ELSE 0 END) AS ImprovingPosts,
    SUM(CASE WHEN cpa.Trend = 'Declining' THEN 1 ELSE 0 END) AS DecliningPosts,
    SUM(CASE WHEN cpa.Trend = 'Stable' THEN 1 ELSE 0 END) AS StablePosts,
    SUM(CASE WHEN cpa.VisibilityLevel = 'High Visibility' THEN 1 ELSE 0 END) AS HighVisibilityPosts,
    SUM(CASE WHEN cpa.VisibilityLevel = 'Medium Visibility' THEN 1 ELSE 0 END) AS MediumVisibilityPosts,
    SUM(CASE WHEN cpa.VisibilityLevel = 'Low Visibility' THEN 1 ELSE 0 END) AS LowVisibilityPosts,
    SUM(CASE WHEN cpa.PostYear = 'Recent' THEN 1 ELSE 0 END) AS RecentPosts,
    SUM(CASE WHEN cpa.PostYear = '2022' THEN 1 ELSE 0 END) AS Posts2022,
    SUM(CASE WHEN cpa.PostYear = '2021' THEN 1 ELSE 0 END) AS Posts2021,
    SUM(CASE WHEN cpa.AnswerStatus = 'Has Answers' THEN 1 ELSE 0 END) AS PostsWithAnswers,
    SUM(CASE WHEN cpa.AnswerStatus = 'No Answers' THEN 1 ELSE 0 END) AS PostsWithoutAnswers,
    SUM(CASE WHEN cpa.CommentStatus = 'Has Comments' THEN 1 ELSE 0 END) AS PostsWithComments,
    SUM(CASE WHEN cpa.CommentStatus = 'No Comments' THEN 1 ELSE 0 END) AS PostsWithoutComments,
    SUM(CASE WHEN cpa.GlobalScoreRank <= 10 THEN 1 ELSE 0 END) AS Top10RankedPosts,
    SUM(CASE WHEN cpa.GlobalViewRank <= 50 THEN 1 ELSE 0 END) AS Top50ViewedPosts,
    SUM(CASE WHEN cpa.CumulativeScore >= 100 THEN 1 ELSE 0 END) AS HighCumulativeScorePosts
FROM UserStats ua
JOIN ComplexPostAnalysis cpa ON ua.UserId = cpa.OwnerUserId
ORDER BY AuthorTotalScore DESC;

-- Additional complex query part for performance testing involving multiple complex operations
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    u.DisplayName AS AuthorName,
    u.Reputation,
    COALESCE(b.Name, 'No Badge') AS RecentBadge,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.UserId = u.Id) THEN 'Author Commented'
        ELSE 'No Author Comment'
    END AS AuthorCommentStatus,
    CASE 
        WHEN p.PostTypeId = 1 THEN 
            (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2)
        ELSE 0 
    END AS AnswerCount,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Q with Accepted Answer'
        WHEN p.PostTypeId = 1 THEN 'Q without Accepted Answer'
        ELSE 'Not a Question'
    END AS QuestionStatus,
    DATEDIFF('day', p.CreationDate, NOW()) AS AgeInDays,
    CASE 
        WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
        WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Average'
        ELSE 'Average'
    END AS ScoreComparison,
    COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2), 0) AS UpVotes,
    COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3), 0) AS DownVotes,
    CASE 
        WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
            (SELECT COUNT(*) FROM UNNEST(SPLIT(p.Tags, '<')) AS tag WHERE tag != '') 
        ELSE 0 
    END AS TagCount,
    CASE 
        WHEN (COALESCE(p.ViewCount, 0) > 0) AND (p.Score > 0) THEN 
            (COALESCE(p.Score, 0) * 100.0 / COALESCE(p.ViewCount, 1))
        ELSE 0 
    END AS ScoreToViewRatio,
    CASE 
        WHEN p.CreationDate > DATE_SUB(NOW(), INTERVAL 1 WEEK) THEN 'This Week'
        WHEN p.CreationDate > DATE_SUB(NOW(), INTERVAL 1 MONTH) THEN 'This Month'
        WHEN p.CreationDate > DATE_SUB(NOW(), INTERVAL 3 MONTH) THEN 'This Quarter'
        ELSE 'Older'
    END AS TimeBucket,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = p.Id 
            AND ph.PostHistoryTypeId IN (1, 4, 5, 6) 
            AND ph.CreationDate > DATE_SUB(NOW(), INTERVAL 1 YEAR)
        ) THEN 'Recently Edited'
        ELSE 'Not Recently Edited'
    END AS EditStatus,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Date > DATE_SUB(NOW(), INTERVAL 1 YEAR)), 
        0
    ) AS RecentBadges,
    CASE 
        WHEN u.Reputation > 10000 THEN 'Elite User'
        WHEN u.Reputation > 1000 THEN 'Veteran User'
        WHEN u.Reputation > 100 THEN 'Regular User'
        ELSE 'New User'
    END AS UserTier,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS GlobalRank,
    RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS UserRank,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
    NTILE(10) OVER (ORDER BY p.Score) AS ScorePercentile,
    p.Body,
    p.Tags
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
    SELECT b.UserId, b.Name, b.Date,
           ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
) b ON u.Id = b.UserId AND b.rn = 1
WHERE p.PostTypeId IN (1, 2)
AND (p.Score > 0 OR p.ViewCount > 0)
AND p.CreationDate > DATE_SUB(NOW(), INTERVAL 5 YEAR)
ORDER BY p.Score DESC, p.CreationDate DESC;