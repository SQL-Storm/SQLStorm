-- {"query": "29019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1922} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as ActivityScore,
        CASE 
            WHEN p.Score > 100 THEN 'Highly_Voted'
            WHEN p.Score > 50 THEN 'Moderately_Voted'
            WHEN p.Score > 0 THEN 'Slightly_Voted'
            ELSE 'No_Votes'
        END as VotingCategory,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostRank,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreQuartile
    FROM Posts p
    WHERE p.CreationDate >= '2010-01-01'::timestamp
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT ps.PostId) as TotalPosts,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(ps.Score) as TotalScore,
        AVG(ps.Score) as AvgScore,
        MAX(ps.CreationDate) as LastPostDate,
        COUNT(DISTINCT ps.Tags) as UniqueTags,
        STRING_AGG(DISTINCT ps.Tags, ',') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT ps.PostId) > 100 THEN 'Highly_Active'
            WHEN COUNT(DISTINCT ps.PostId) > 50 THEN 'Moderately_Active'
            WHEN COUNT(DISTINCT ps.PostId) > 10 THEN 'Occasionally_Active'
            ELSE 'New_User'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
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
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as PostsWithTag,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreForTag,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
ComplexActivity AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.OwnerUserId,
        ps.PostType,
        ps.ActivityScore,
        ps.VotingCategory,
        ps.ScoreQuartile,
        ps.PostRank,
        ps.PrevScore,
        u.DisplayName as OwnerName,
        u.Reputation,
        u.Views as UserViews,
        u.TotalPosts,
        u.QuestionCount,
        u.AnswerCount,
        u.TotalScore,
        u.ActivityLevel,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM PostStats) THEN 'Above_Avg'
            ELSE 'Below_Avg'
        END as ScoreVsAvg,
        CASE 
            WHEN ps.PostRank = 1 THEN 'First_Post'
            WHEN ps.PostRank = (SELECT MAX(PostRank) FROM PostStats ps2 WHERE ps2.OwnerUserId = ps.OwnerUserId) THEN 'Last_Post'
            ELSE 'Middle_Post'
        END as PostPosition,
        RANK() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as UserPostRank,
        LAG(ps.CreationDate, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as PrevPostTime,
        (ps.CreationDate - LAG(ps.CreationDate, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate)) as TimeBetweenPosts,
        COALESCE(
            (SELECT ta.TagPopularity FROM TagAnalysis ta WHERE ta.TagName IN (
                SELECT DISTINCT unnest(string_to_array(ps.Tags, '>')) 
                WHERE unnest(string_to_array(ps.Tags, '>')) != ''
            ) LIMIT 1), 'Unknown'
        ) as MainTagPopularity
    FROM PostStats ps
    JOIN UserActivity u ON ps.OwnerUserId = u.UserId
    WHERE ps.PostId NOT IN (SELECT DISTINCT ParentId FROM Posts WHERE ParentId IS NOT NULL)
    AND ps.Title IS NOT NULL
),
FinalAnalysis AS (
    SELECT 
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.OwnerUserId,
        ca.OwnerName,
        ca.Reputation,
        ca.UserViews,
        ca.TotalPosts,
        ca.QuestionCount,
        ca.AnswerCount,
        ca.TotalScore,
        ca.ActivityLevel,
        ca.PostType,
        ca.ActivityScore,
        ca.VotingCategory,
        ca.ScoreQuartile,
        ca.ScoreVsAvg,
        ca.PostPosition,
        ca.UserPostRank,
        ca.TimeBetweenPosts,
        ca.MainTagPopularity,
        CASE 
            WHEN ca.Score > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) FROM PostStats) THEN 'Top_25%'
            WHEN ca.Score > (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Score) FROM PostStats) THEN 'Top_50%'
            WHEN ca.Score > (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Score) FROM PostStats) THEN 'Top_75%'
            ELSE 'Bottom_25%'
        END as ScorePercentile,
        CASE 
            WHEN ca.TimeBetweenPosts IS NULL THEN 'First_Post'
            WHEN ca.TimeBetweenPosts < INTERVAL '1 day' THEN 'Frequent_Poster'
            ELSE 'Regular_Poster'
        END as PostingFrequency
    FROM ComplexActivity ca
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.OwnerName,
    fa.Reputation,
    fa.TotalPosts,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.TotalScore,
    fa.ActivityLevel,
    fa.PostType,
    fa.ActivityScore,
    fa.VotingCategory,
    fa.ScoreQuartile,
    fa.ScoreVsAvg,
    fa.PostPosition,
    fa.TimeBetweenPosts,
    fa.MainTagPopularity,
    fa.ScorePercentile,
    fa.PostingFrequency,
    'Post Analysis Complete' as Status,
    CURRENT_TIMESTAMP as AnalysisTime,
    CASE 
        WHEN fa.Score > 100 AND fa.ViewCount > 1000 THEN 'Highly_Visible_Expert_Post'
        WHEN fa.Score > 50 AND fa.ViewCount > 500 THEN 'Popular_Expert_Post'
        WHEN fa.Score > 0 AND fa.ViewCount > 100 THEN 'Noticeable_Post'
        WHEN fa.Score > -10 AND fa.ViewCount > 10 THEN 'Minor_Post'
        ELSE 'Low_Interest_Post'
    END as PostImpact,
    ROW_NUMBER() OVER (ORDER BY fa.Score DESC, fa.ViewCount DESC) as OverallRank,
    RANK() OVER (PARTITION BY fa.ActivityLevel ORDER BY fa.Score DESC) as ActivityLevelRank
FROM FinalAnalysis fa
WHERE fa.PostType IN ('Question', 'Answer')
  AND (fa.Score > 0 OR fa.ViewCount > 0)
  AND fa.OwnerName IS NOT NULL
  AND fa.Title IS NOT NULL
  AND (fa.Reputation > 0 OR fa.TotalPosts > 0)
  AND fa.MainTagPopularity IS NOT NULL
  AND (fa.PostingFrequency IN ('Frequent_Poster', 'Regular_Poster') OR fa.PostingFrequency IS NULL)
ORDER BY fa.Score DESC, fa.ViewCount DESC, fa.ActivityScore DESC
LIMIT 5000;