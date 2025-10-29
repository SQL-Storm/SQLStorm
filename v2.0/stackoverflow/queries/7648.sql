WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as TotalAnswers,
        COUNT(DISTINCT b.Id) as TotalBadges,
        MAX(p.CreationDate) as LastPostDate,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - MAX(p.CreationDate)))/86400 AS DaysSinceLastPost,
        RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
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
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        COALESCE(p.AnswerCount, 0) / NULLIF(p.ViewCount, 0) as AnswerToViewRatio,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Rated'
            WHEN p.Score > 50 THEN 'Moderately Rated'
            WHEN p.Score > 0 THEN 'Low Rated'
            ELSE 'Unrated'
        END as RatingCategory,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate))/86400 AS AgeInDays
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Less Popular'
            ELSE 'Rare'
        END as PopularityLevel,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
UserPostSummary AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(p.Id) as PostCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.ViewCount) as MaxViews,
        MIN(p.CreationDate) as FirstPostDate,
        MAX(p.CreationDate) as LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName
),
ComplexAnalysis AS (
    SELECT 
        pas.PostId,
        pas.Title,
        pas.Score,
        pas.ViewCount,
        pas.AnswerCount,
        pas.CommentCount,
        pas.FavoriteCount,
        pas.CreationDate,
        pas.OwnerUserId,
        pas.PostCategory,
        pas.AnswerToViewRatio,
        pas.RatingCategory,
        pas.AgeInDays,
        uas.DisplayName as OwnerDisplayName,
        uas.Reputation as OwnerReputation,
        uas.TotalPosts as OwnerTotalPosts,
        uas.TotalBadges as OwnerTotalBadges,
        ta.TagName,
        ta.TagCount,
        ta.PopularityLevel,
        ups.PostCount as UserPostCount,
        ups.TotalScore as UserTotalScore,
        ups.AvgScore as UserAvgScore
    FROM PostAnalysis pas
    LEFT JOIN UserActivityStats uas ON pas.OwnerUserId = uas.UserId
    LEFT JOIN Users u ON u.Id = pas.OwnerUserId
    LEFT JOIN (
        SELECT 
            p.Id as PostId,
            t.TagName,
            t.Count as TagCount,
            CASE 
                WHEN t.Count > 1000 THEN 'Popular'
                WHEN t.Count > 500 THEN 'Moderate'
                WHEN t.Count > 100 THEN 'Less Popular'
                ELSE 'Rare'
            END as PopularityLevel
        FROM Posts p
        JOIN Tags t ON p.Tags IS NOT NULL AND p.Tags LIKE '%' || t.TagName || '%'
        WHERE p.Tags IS NOT NULL
    ) ta ON pas.PostId = ta.PostId
    LEFT JOIN UserPostSummary ups ON pas.OwnerUserId = ups.UserId
)
SELECT *
FROM (
    SELECT 
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.CreationDate,
        ca.OwnerDisplayName,
        ca.OwnerReputation,
        ca.OwnerTotalPosts,
        ca.OwnerTotalBadges,
        ca.TagName,
        ca.TagCount,
        ca.PopularityLevel,
        ca.UserPostCount,
        ca.UserTotalScore,
        ca.UserAvgScore,
        ca.AnswerToViewRatio,
        ca.RatingCategory,
        ca.AgeInDays,
        CASE 
            WHEN ca.AgeInDays > 365 AND ca.Score > 100 THEN 'Veteran High Scorer'
            WHEN ca.AgeInDays > 365 AND ca.Score > 50 THEN 'Veteran Moderate Scorer'
            WHEN ca.AgeInDays <= 365 AND ca.Score > 100 THEN 'Recent High Scorer'
            WHEN ca.AgeInDays <= 365 AND ca.Score > 50 THEN 'Recent Moderate Scorer'
            ELSE 'Other'
        END as PerformanceCategory,
        ROW_NUMBER() OVER (PARTITION BY ca.OwnerUserId ORDER BY ca.Score DESC) as PostRankInUser,
        NTILE(4) OVER (ORDER BY ca.Score DESC) as ScoreQuartile,
        SUM(ca.Score) OVER (PARTITION BY ca.OwnerUserId ORDER BY ca.CreationDate) as CumulativeScore,
        LAG(ca.Score, 1) OVER (PARTITION BY ca.OwnerUserId ORDER BY ca.CreationDate) as PrevScore,
        LEAD(ca.Score, 1) OVER (PARTITION BY ca.OwnerUserId ORDER BY ca.CreationDate) as NextScore,
        CASE 
            WHEN ca.Score > (SELECT AVG(p.Score) FROM PostAnalysis p) THEN 'Above Average'
            WHEN ca.Score < (SELECT AVG(p.Score) FROM PostAnalysis p) THEN 'Below Average'
            ELSE 'Average'
        END as ScoreComparison,
        CONCAT(
            'Post ', ca.PostId, 
            ' by ', ca.OwnerDisplayName, 
            ' (', ca.Score, ' points)'
        ) as PostSummary,
        CASE
            WHEN ca.AnswerToViewRatio > 0.1 AND ca.AgeInDays < 180 THEN 'Active Engagement'
            WHEN ca.AnswerToViewRatio < 0.05 AND ca.AgeInDays > 180 THEN 'Legacy Content'
            WHEN ca.AnswerToViewRatio BETWEEN 0.05 AND 0.1 THEN 'Stable Engagement'
            ELSE 'Other'
        END as EngagementType,
        CASE WHEN ca.PostId IS NULL THEN 1 ELSE 0 END as IsTotalRow
    FROM ComplexAnalysis ca
    WHERE ca.OwnerDisplayName IS NOT NULL
    GROUP BY
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.CreationDate,
        ca.OwnerDisplayName,
        ca.OwnerReputation,
        ca.OwnerTotalPosts,
        ca.OwnerTotalBadges,
        ca.TagName,
        ca.TagCount,
        ca.PopularityLevel,
        ca.UserPostCount,
        ca.UserTotalScore,
        ca.UserAvgScore,
        ca.AnswerToViewRatio,
        ca.RatingCategory,
        ca.AgeInDays,
        ca.OwnerUserId
    HAVING ca.Score > 0

    UNION ALL

    SELECT 
        NULL as PostId,
        'TOTAL SUMMARY' as Title,
        SUM(ca.Score) as Score,
        SUM(ca.ViewCount) as ViewCount,
        SUM(ca.AnswerCount) as AnswerCount,
        SUM(ca.CommentCount) as CommentCount,
        SUM(ca.FavoriteCount) as FavoriteCount,
        NULL as CreationDate,
        'ALL USERS' as OwnerDisplayName,
        NULL as OwnerReputation,
        COUNT(DISTINCT ca.OwnerUserId) as OwnerTotalPosts,
        COUNT(DISTINCT ca.OwnerUserId) as OwnerTotalBadges,
        NULL as TagName,
        NULL as TagCount,
        NULL as PopularityLevel,
        NULL as UserPostCount,
        SUM(ca.UserTotalScore) as UserTotalScore,
        AVG(ca.UserAvgScore) as UserAvgScore,
        NULL as AnswerToViewRatio,
        'OVERALL' as RatingCategory,
        NULL as AgeInDays,
        'COMBINED' as PerformanceCategory,
        NULL as PostRankInUser,
        NULL as ScoreQuartile,
        NULL as CumulativeScore,
        NULL as PrevScore,
        NULL as NextScore,
        NULL as ScoreComparison,
        'COMBINED DATA' as PostSummary,
        'TOTALS' as EngagementType,
        1 as IsTotalRow
    FROM ComplexAnalysis ca
) t
ORDER BY 
    IsTotalRow,
    Score DESC,
    CreationDate DESC
LIMIT 1000;