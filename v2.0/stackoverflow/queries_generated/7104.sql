-- {"query": "7104.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2407} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        COALESCE(p.Title, 'No Title') as CleanTitle,
        NULLIF(p.Tags, '') as CleanTags,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysActive,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' AND p.CreationDate < '2023-01-01'
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.PostId) as TotalPosts,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) as TotalQuestions,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) as TotalAnswers,
        SUM(ps.Score) as TotalScore,
        AVG(ps.Score) as AvgScore,
        MAX(ps.CreationDate) as LastActivity,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel
    FROM Users u
    LEFT JOIN PostStats ps ON ps.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        ps.PostTypeDesc,
        ps.CleanTitle,
        ps.CleanTags,
        ps.DaysActive,
        ps.ScoreCategory,
        ps.UserPostRank,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        u.ReputationLevel as OwnerReputationLevel,
        LAG(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as PrevScore,
        LEAD(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as NextScore,
        AVG(ps.Score) OVER (PARTITION BY ps.OwnerUserId) as UserAvgScore,
        COUNT(*) OVER (PARTITION BY ps.OwnerUserId) as UserTotalPosts,
        NTH_VALUE(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as UserBestScore,
        NTH_VALUE(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as UserWorstScore
    FROM PostStats ps
    INNER JOIN UserActivity u ON ps.OwnerUserId = u.UserId
    WHERE ps.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            ELSE 'Public'
        END as TagType,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularRank
    FROM Tags t
    WHERE t.Count > 100 AND t.TagName IS NOT NULL
),
ComplexVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId IN (2, 3) THEN 'Reputation Vote'
            WHEN v.VoteTypeId IN (8, 9) THEN 'Bounty Vote'
            WHEN v.VoteTypeId = 5 THEN 'Favorite Vote'
            ELSE 'Other Vote'
        END as VoteCategory,
        DENSE_RANK() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) as VoteRank,
        COUNT(*) OVER (PARTITION BY v.PostId) as TotalVotesOnPost,
        AVG(v.BountyAmount) OVER (PARTITION BY v.PostId) as AvgBountyPerPost
    FROM Votes v
    WHERE v.CreationDate >= '2020-01-01' AND v.CreationDate < '2023-01-01'
),
FinalPostAnalysis AS (
    SELECT 
        pa.PostId,
        pa.PostTypeId,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.CreationDate,
        pa.LastActivityDate,
        pa.Title,
        pa.Tags,
        pa.PostTypeDesc,
        pa.CleanTitle,
        pa.CleanTags,
        pa.DaysActive,
        pa.ScoreCategory,
        pa.UserPostRank,
        pa.OwnerDisplayName,
        pa.OwnerReputation,
        pa.OwnerReputationLevel,
        pa.PrevScore,
        pa.NextScore,
        pa.UserAvgScore,
        pa.UserTotalPosts,
        pa.UserBestScore,
        pa.UserWorstScore,
        COALESCE(ce.TagCount, 0) as RelatedTagCount,
        COALESCE(ce.TagType, 'Unknown') as RelatedTagType,
        CASE 
            WHEN pa.Score > pa.UserAvgScore THEN 'Above Average'
            WHEN pa.Score < pa.UserAvgScore THEN 'Below Average'
            ELSE 'Average'
        END as PerformanceStatus,
        CASE 
            WHEN pa.PostTypeId = 1 AND pa.AnswerCount > 5 THEN 'Highly Active Q'
            WHEN pa.PostTypeId = 2 AND pa.Score > 10 THEN 'High Scoring A'
            ELSE 'Regular Post'
        END as PostClassification,
        CASE 
            WHEN pa.DaysActive > 30 THEN 'Long Lived'
            WHEN pa.DaysActive <= 7 THEN 'Recently Active'
            ELSE 'Medium Lifespan'
        END as ActivityLifespan,
        CASE 
            WHEN pa.CreationDate BETWEEN '2022-01-01' AND '2022-12-31' THEN '2022'
            WHEN pa.CreationDate BETWEEN '2021-01-01' AND '2021-12-31' THEN '2021'
            ELSE 'Other Year'
        END as PostYearGroup
    FROM PostAnalysis pa
    LEFT JOIN TagAnalysis ce ON pa.CleanTags LIKE '%' || ce.TagName || '%'
    WHERE pa.Score IS NOT NULL
)
SELECT 
    fpa.PostId,
    fpa.PostTypeId,
    fpa.OwnerUserId,
    fpa.Score,
    fpa.ViewCount,
    fpa.AnswerCount,
    fpa.CommentCount,
    fpa.FavoriteCount,
    fpa.CreationDate,
    fpa.LastActivityDate,
    fpa.Title,
    fpa.Tags,
    fpa.PostTypeDesc,
    fpa.CleanTitle,
    fpa.CleanTags,
    fpa.DaysActive,
    fpa.ScoreCategory,
    fpa.UserPostRank,
    fpa.OwnerDisplayName,
    fpa.OwnerReputation,
    fpa.OwnerReputationLevel,
    fpa.PrevScore,
    fpa.NextScore,
    fpa.UserAvgScore,
    fpa.UserTotalPosts,
    fpa.UserBestScore,
    fpa.UserWorstScore,
    fpa.RelatedTagCount,
    fpa.RelatedTagType,
    fpa.PerformanceStatus,
    fpa.PostClassification,
    fpa.ActivityLifespan,
    fpa.PostYearGroup,
    -- Complex calculations and expressions
    CASE 
        WHEN fpa.ViewCount IS NOT NULL AND fpa.Score IS NOT NULL AND fpa.ViewCount > 0 
        THEN (fpa.Score * 100.0 / fpa.ViewCount) 
        ELSE NULL 
    END as ScorePerView,
    CASE 
        WHEN fpa.UserTotalPosts > 0 
        THEN (fpa.UserBestScore * 100.0 / fpa.UserTotalPosts) 
        ELSE 0 
    END as EfficiencyScore,
    LTRIM(RTRIM(COALESCE(fpa.CleanTitle, 'No Title'))) as TrimmedTitle,
    UPPER(COALESCE(fpa.OwnerDisplayName, 'Anonymous')) as UpperDisplayName,
    CONCAT('Post_', fpa.PostId, '_User_', fpa.OwnerUserId) as PostUserIdentifier,
    COALESCE(fpa.FavoriteCount, 0) + COALESCE(fpa.CommentCount, 0) as EngagementCount,
    DATEDIFF(day, fpa.CreationDate, GETDATE()) as DaysSinceCreation,
    -- Set operators and complicated predicates
    CASE 
        WHEN EXISTS (SELECT 1 FROM ComplexVotes cv WHERE cv.PostId = fpa.PostId AND cv.VoteTypeId IN (2, 3)) 
        THEN 'Has Reputation Vote'
        ELSE 'No Rep Vote'
    END as RepVoteIndicator,
    CASE 
        WHEN fpa.Score > (SELECT AVG(Score) FROM FinalPostAnalysis WHERE PostTypeId = fpa.PostTypeId) 
        THEN 'Above Avg Score'
        ELSE 'Below Avg Score'
    END as AboveAvgScoreFlag,
    CASE 
        WHEN (fpa.DaysActive > 30 OR fpa.UserTotalPosts > 10) AND fpa.Score > 50 
        THEN 'High Value'
        ELSE 'Standard Value'
    END as ValueCategory
FROM FinalPostAnalysis fpa
WHERE 
    (fpa.Score > 0 OR fpa.Score IS NULL) AND 
    (fpa.Views IS NOT NULL OR fpa.ViewCount IS NOT NULL) AND
    (COALESCE(fpa.OwnerDisplayName, '') != '' OR COALESCE(fpa.CleanTitle, '') != '') AND
    fpa.PostYearGroup IN ('2021', '2022') AND
    (fpa.UserAvgScore > 0 OR fpa.UserBestScore > 0)
ORDER BY 
    fpa.Score DESC, 
    fpa.CreationDate DESC,
    fpa.OwnerReputation DESC
LIMIT 10000;