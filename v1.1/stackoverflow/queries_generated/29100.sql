-- {"query": "29100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2313} 
WITH UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        COUNT(DISTINCT v.Id) AS Votes,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate)) AS DaysSinceLastPost,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        PERCENT_RANK() OVER (ORDER BY u.Reputation) AS RepPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 10 THEN 'Low Voted'
            ELSE 'Very Low Voted'
        END AS VoteCategory,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        CASE 
            WHEN p.AnswerCount > 0 THEN (p.Score * 1.0 / NULLIF(p.AnswerCount, 0))
            ELSE 0
        END AS ScorePerAnswer,
        LENGTH(p.Body) AS BodyLength,
        SUBSTRING(p.Body, 1, 100) AS BodyPreview,
        COALESCE(p.Tags, '') AS Tags,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0
        END AS TagCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) AS DaysOld,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankPerType
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
UserPerformanceMetrics AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.Votes,
        uas.PostRank,
        uas.RepPercentile,
        CASE 
            WHEN uas.TotalPosts > 100 THEN 'Highly Active'
            WHEN uas.TotalPosts > 50 THEN 'Active'
            WHEN uas.TotalPosts > 10 THEN 'Moderate'
            ELSE 'Beginner'
        END AS ActivityLevel,
        CASE 
            WHEN uas.Questions > 0 AND uas.Answers > 0 THEN 'Both'
            WHEN uas.Questions > 0 THEN 'Questioner'
            WHEN uas.Answers > 0 THEN 'Answerer'
            ELSE 'Neither'
        END AS RoleType,
        COALESCE(100.0 * uas.Answers / NULLIF(uas.Questions, 0), 0) AS AnswerQuestionRatio,
        COALESCE(100.0 * uas.Badges / NULLIF(uas.Votes, 0), 0) AS BadgeToVoteRatio
    FROM UserActivitySummary uas
),
ComplexPostAnalysis AS (
    SELECT 
        pca.PostId,
        pca.Title,
        pca.Score,
        pca.ViewCount,
        pca.CommentCount,
        pca.FavoriteCount,
        pca.PostType,
        pca.VoteCategory,
        pca.AnswerCount,
        pca.ScorePerAnswer,
        pca.BodyLength,
        pca.BodyPreview,
        pca.TagCount,
        pca.PostStatus,
        pca.DaysOld,
        pca.ScoreRankPerType,
        LAG(pca.Score, 1) OVER (ORDER BY pca.Score DESC) AS PrevScore,
        LEAD(pca.Score, 1) OVER (ORDER BY pca.Score DESC) AS NextScore,
        AVG(pca.Score) OVER (ORDER BY pca.Score ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS MovingAvgScore,
        NTILE(4) OVER (ORDER BY pca.Score) AS ScoreQuartile,
        CASE 
            WHEN pca.Score >= (SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE CreationDate >= '2015-01-01')
            THEN 'Top 5% Score'
            WHEN pca.Score >= (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE CreationDate >= '2015-01-01')
            THEN 'Top 10% Score'
            WHEN pca.Score >= (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE CreationDate >= '2015-01-01')
            THEN 'Top 25% Score'
            ELSE 'Below 25% Score'
        END AS ScorePercentileCategory,
        CASE 
            WHEN pca.BodyLength > 1000 THEN 'Long Body'
            WHEN pca.BodyLength > 500 THEN 'Medium Body'
            WHEN pca.BodyLength > 100 THEN 'Short Body'
            ELSE 'Very Short Body'
        END AS BodyLengthCategory,
        CASE 
            WHEN pca.TagCount > 10 THEN 'Many Tags'
            WHEN pca.TagCount > 5 THEN 'Moderate Tags'
            WHEN pca.TagCount > 1 THEN 'Few Tags'
            ELSE 'No Tags'
        END AS TagCategory
    FROM PostComplexityAnalysis pca
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.TotalPosts,
    u.Questions,
    u.Answers,
    u.Comments,
    u.Badges,
    u.Votes,
    u.ActivityLevel,
    u.RoleType,
    u.AnswerQuestionRatio,
    u.BadgeToVoteRatio,
    COALESCE(cpa.PostId, 0) AS TopPostId,
    COALESCE(cpa.Title, 'N/A') AS TopPostTitle,
    COALESCE(cpa.Score, 0) AS TopPostScore,
    COALESCE(cpa.ViewCount, 0) AS TopPostViews,
    COALESCE(cpa.CommentCount, 0) AS TopPostComments,
    COALESCE(cpa.FavoriteCount, 0) AS TopPostFavorites,
    COALESCE(cpa.PostType, 'N/A') AS TopPostType,
    COALESCE(cpa.VoteCategory, 'N/A') AS TopPostVoteCategory,
    COALESCE(cpa.BodyLength, 0) AS TopPostBodyLength,
    COALESCE(cpa.TagCount, 0) AS TopPostTagCount,
    COALESCE(cpa.PostStatus, 'N/A') AS TopPostStatus,
    COALESCE(cpa.DaysOld, 0) AS TopPostAgeDays,
    COALESCE(cpa.ScorePercentileCategory, 'N/A') AS TopPostScorePercentile,
    COALESCE(cpa.BodyLengthCategory, 'N/A') AS TopPostBodyCategory,
    COALESCE(cpa.TagCategory, 'N/A') AS TopPostTagCategory,
    CASE 
        WHEN u.Answers > 0 AND u.Questions > 0 THEN (u.Answers * 1.0 / NULLIF(u.Questions, 0))
        ELSE 0 
    END AS AnswerToQuestionRatio,
    CASE 
        WHEN u.Badges > 0 AND u.Votes > 0 THEN (u.Badges * 1.0 / NULLIF(u.Votes, 0))
        ELSE 0 
    END AS BadgeToVoteRatio,
    CASE 
        WHEN u.TotalPosts > 0 THEN (u.Answers * 1.0 / NULLIF(u.TotalPosts, 0))
        ELSE 0 
    END AS AnswerPercentage,
    CASE 
        WHEN u.RepPercentile > 0.9 THEN 'Top 10%'
        WHEN u.RepPercentile > 0.75 THEN 'Top 25%'
        WHEN u.RepPercentile > 0.5 THEN 'Top 50%'
        ELSE 'Below 50%'
    END AS RepPercentileCategory,
    CASE 
        WHEN cpa.Score IS NOT NULL THEN 
            CASE WHEN cpa.Score > cpa.PrevScore THEN 'Increased' 
                 WHEN cpa.Score < cpa.PrevScore THEN 'Decreased' 
                 ELSE 'Same' END
        ELSE 'No Data'
    END AS ScoreChangeStatus,
    COALESCE(cpa.MovingAvgScore, 0) AS MovingAverageScore,
    COALESCE(cpa.ScoreQuartile, 0) AS ScoreQuartile,
    CASE 
        WHEN cpa.Score >= 100 AND u.PostRank <= 50 THEN 'High Scoring Active User'
        WHEN cpa.Score >= 50 AND u.PostRank <= 100 THEN 'Moderate Scoring Active User'
        WHEN u.PostRank <= 10 THEN 'Top Poster'
        ELSE 'Regular User'
    END AS UserClassification
FROM UserPerformanceMetrics u
LEFT JOIN (
    SELECT 
        cpa.*,
        ROW_NUMBER() OVER (PARTITION BY 1 ORDER BY cpa.Score DESC) AS PostRank
    FROM ComplexPostAnalysis cpa
) cpa ON 1=1 
WHERE u.UserRank <= 100 AND (cpa.PostRank = 1 OR cpa.PostRank IS NULL)
ORDER BY u.TotalPosts DESC, u.Reputation DESC
LIMIT 50;