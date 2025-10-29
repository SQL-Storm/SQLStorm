-- {"query": "7810.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3047} 
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDesc,
        COALESCE(p.Title, 'No Title') AS CleanTitle,
        LENGTH(p.Body) AS BodyLength,
        CASE 
            WHEN p.Score >= 100 THEN 'High Engagement'
            WHEN p.Score >= 10 THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END AS EngagementLevel,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        NTILE(4) OVER (ORDER BY p.ViewCount) AS ViewQuartile,
        CASE 
            WHEN p.AnswerCount > 0 THEN (p.Score * 1.0 / p.AnswerCount)
            ELSE NULL 
        END AS ScorePerAnswer,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) AS DaysSinceLastActivity,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN TRIM(BOTH '<>' FROM p.Tags)
            ELSE NULL 
        END AS CleanTags,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) AS PrevScore
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount AS UserViews,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        SUM(COALESCE(ps.Score, 0)) AS TotalScore,
        AVG(COALESCE(ps.Score, 0)) AS AvgPostScore,
        MAX(ps.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS AnswerCount,
        STRING_AGG(DISTINCT ps.PostTypeDesc, ', ') AS PostTypes,
        COALESCE(SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(DISTINCT ps.Id), 0), 0) AS QuestionPercentage,
        CASE 
            WHEN COUNT(DISTINCT ps.Id) = 0 THEN 'No Posts'
            WHEN COUNT(DISTINCT ps.Id) <= 10 THEN 'Beginner'
            WHEN COUNT(DISTINCT ps.Id) <= 50 THEN 'Intermediate'
            WHEN COUNT(DISTINCT ps.Id) <= 200 THEN 'Advanced'
            ELSE 'Expert'
        END AS UserExperienceLevel,
        CASE 
            WHEN u.Reputation >= 100000 THEN 'Master'
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Novice'
            ELSE 'Beginner'
        END AS ReputationTier,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.AccountId
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id AS PostId,
        ps.OwnerUserId,
        ps.Title AS PostTitle,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.PostTypeDesc,
        ps.PostStatus,
        ps.EngagementLevel,
        ps.UserPostRank,
        ps.UserPostRank,
        ps.TotalUserPosts,
        ps.AvgUserScore,
        ps.ViewQuartile,
        ps.ScorePerAnswer,
        ps.DaysSinceLastActivity,
        ps.CleanTags,
        CASE 
            WHEN ps.Tags IS NOT NULL THEN ARRAY_LENGTH(string_to_array(ps.CleanTags, '><'), 1)
            ELSE 0
        END AS TagCount,
        CASE 
            WHEN ps.ScorePerAnswer IS NOT NULL THEN ps.ScorePerAnswer * 100.0
            ELSE NULL 
        END AS ScorePerAnswerPercentage,
        ps.PrevScore,
        CASE 
            WHEN ps.Score > COALESCE(ps.PrevScore, 0) THEN 'Increased'
            WHEN ps.Score < COALESCE(ps.PrevScore, 0) THEN 'Decreased'
            ELSE 'Same'
        END AS ScoreChangeTrend,
        CASE 
            WHEN ps.Score >= 50 AND ps.AnswerCount > 0 AND ps.CommentCount > 0 THEN 'High Quality'
            WHEN ps.Score >= 10 AND ps.AnswerCount > 0 THEN 'Medium Quality'
            WHEN ps.Score >= 1 THEN 'Low Quality'
            ELSE 'No Score'
        END AS QualityAssessment,
        CASE 
            WHEN ps.ViewQuartile = 1 THEN 'Low Viewership'
            WHEN ps.ViewQuartile = 2 THEN 'Medium Viewership'
            WHEN ps.ViewQuartile = 3 THEN 'High Viewership'
            ELSE 'Very High Viewership'
        END AS ViewershipLevel,
        CASE 
            WHEN ps.DaysSinceLastActivity > 30 THEN 'Inactive'
            WHEN ps.DaysSinceLastActivity > 7 THEN 'Moderately Active'
            ELSE 'Active'
        END AS ActivityStatus
    FROM PostStats ps
    WHERE ps.PostTypeDesc IN ('Question', 'Answer')
),
FinalAnalysis AS (
    SELECT 
        cpa.PostId,
        cpa.OwnerUserId,
        cpa.PostTitle,
        cpa.Score,
        cpa.ViewCount,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.CreationDate,
        cpa.LastActivityDate,
        cpa.PostTypeDesc,
        cpa.PostStatus,
        cpa.EngagementLevel,
        cpa.UserPostRank,
        cpa.TotalUserPosts,
        cpa.AvgUserScore,
        cpa.ViewQuartile,
        cpa.ScorePerAnswer,
        cpa.ScorePerAnswerPercentage,
        cpa.DaysSinceLastActivity,
        cpa.CleanTags,
        cpa.TagCount,
        cpa.ScoreChangeTrend,
        cpa.QualityAssessment,
        cpa.ViewershipLevel,
        cpa.ActivityStatus,
        ua.DisplayName AS OwnerDisplayName,
        ua.Reputation,
        ua.UserViews,
        ua.TotalPosts,
        ua.TotalScore,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.PostTypes,
        ua.QuestionPercentage,
        ua.UserExperienceLevel,
        ua.ReputationTier,
        ua.BadgeCount,
        ua.BadgeNames,
        ua.ReputationRank,
        CASE 
            WHEN cpa.ViewCount > 1000 THEN 'Viral'
            WHEN cpa.ViewCount > 500 THEN 'Popular'
            WHEN cpa.ViewCount > 100 THEN 'Notable'
            ELSE 'Normal'
        END AS ViewCategory,
        CASE 
            WHEN cpa.Score > 500 THEN 'Excellent'
            WHEN cpa.Score > 200 THEN 'Good'
            WHEN cpa.Score > 50 THEN 'Fair'
            ELSE 'Poor'
        END AS ReputationCategory,
        DENSE_RANK() OVER (PARTITION BY cpa.PostTypeDesc ORDER BY cpa.ViewCount DESC) AS ViewRankByType
    FROM ComplexPostAnalysis cpa
    JOIN UserActivity ua ON cpa.OwnerUserId = ua.UserId
    WHERE cpa.Score IS NOT NULL AND cpa.ViewCount IS NOT NULL
),
RankedPosts AS (
    SELECT 
        fa.*,
        ROW_NUMBER() OVER (ORDER BY fa.ViewCount DESC) AS GlobalViewRank,
        RANK() OVER (PARTITION BY fa.PostTypeDesc ORDER BY fa.ViewCount DESC) AS TypeViewRank,
        DENSE_RANK() OVER (ORDER BY fa.Score DESC) AS HighScoreRank,
        PERCENT_RANK() OVER (ORDER BY fa.ViewCount) AS ViewPercentile,
        NTILE(10) OVER (ORDER BY fa.Score) AS ScoreDecile,
        CASE 
            WHEN ROW_NUMBER() OVER (ORDER BY fa.ViewCount DESC) <= 10 THEN 'Top 10 Viewed'
            WHEN ROW_NUMBER() OVER (ORDER BY fa.ViewCount DESC) <= 100 THEN 'Top 100 Viewed'
            WHEN ROW_NUMBER() OVER (ORDER BY fa.ViewCount DESC) <= 1000 THEN 'Top 1000 Viewed'
            ELSE 'Below Top 1000'
        END AS ViewImpactCategory,
        CASE 
            WHEN fa.Score >= 1000 THEN 'Legendary'
            WHEN fa.Score >= 500 THEN 'Epic'
            WHEN fa.Score >= 200 THEN 'Great'
            WHEN fa.Score >= 100 THEN 'Good'
            ELSE 'Average'
        END AS ScoreImpactCategory
    FROM FinalAnalysis fa
)
SELECT 
    rp.PostId,
    rp.OwnerUserId,
    rp.PostTitle,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.PostTypeDesc,
    rp.PostStatus,
    rp.EngagementLevel,
    rp.UserPostRank,
    rp.TotalUserPosts,
    rp.AvgUserScore,
    rp.ViewQuartile,
    rp.ScorePerAnswer,
    rp.ScorePerAnswerPercentage,
    rp.DaysSinceLastActivity,
    rp.CleanTags,
    rp.TagCount,
    rp.ScoreChangeTrend,
    rp.QualityAssessment,
    rp.ViewershipLevel,
    rp.ActivityStatus,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.UserViews,
    rp.TotalPosts,
    rp.TotalScore,
    rp.QuestionCount,
    rp.AnswerCount,
    rp.PostTypes,
    rp.QuestionPercentage,
    rp.UserExperienceLevel,
    rp.ReputationTier,
    rp.BadgeCount,
    rp.BadgeNames,
    rp.ReputationRank,
    rp.ViewCategory,
    rp.ReputationCategory,
    rp.ViewRankByType,
    rp.GlobalViewRank,
    rp.TypeViewRank,
    rp.HighScoreRank,
    rp.ViewPercentile,
    rp.ScoreDecile,
    rp.ViewImpactCategory,
    rp.ScoreImpactCategory,
    CASE 
        WHEN rp.TotalScore >= 1000 THEN 'High Performer'
        WHEN rp.TotalScore >= 500 THEN 'Medium Performer'
        WHEN rp.TotalScore >= 100 THEN 'Low Performer'
        ELSE 'Beginner'
    END AS PerformanceLevel,
    COALESCE(rp.OwnerDisplayName, 'Anonymous') AS FinalDisplayName,
    COALESCE(rp.CleanTags, 'No Tags') AS FinalTags,
    CASE 
        WHEN rp.Score >= 100 AND rp.AnswerCount >= 5 THEN TRUE
        ELSE FALSE
    END AS IsHighQualityContributor,
    CASE 
        WHEN rp.ViewCount >= 1000 AND rp.Score >= 50 THEN TRUE
        ELSE FALSE
    END AS IsPopularPost
FROM RankedPosts rp
WHERE rp.PostTypeDesc IN ('Question', 'Answer')
  AND rp.Score IS NOT NULL
  AND (rp.Reputation > 100 OR rp.ViewCount > 50)
  AND rp.PostStatus = 'Active'
GROUP BY 
    rp.PostId, rp.OwnerUserId, rp.PostTitle, rp.Score, rp.ViewCount, rp.AnswerCount, rp.CommentCount, 
    rp.FavoriteCount, rp.CreationDate, rp.LastActivityDate, rp.PostTypeDesc, rp.PostStatus, rp.EngagementLevel, 
    rp.UserPostRank, rp.TotalUserPosts, rp.AvgUserScore, rp.ViewQuartile, rp.ScorePerAnswer, rp.ScorePerAnswerPercentage, 
    rp.DaysSinceLastActivity, rp.CleanTags, rp.TagCount, rp.ScoreChangeTrend, rp.QualityAssessment, rp.ViewershipLevel, 
    rp.ActivityStatus, rp.OwnerDisplayName, rp.Reputation, rp.UserViews, rp.TotalPosts, rp.TotalScore, rp.QuestionCount, 
    rp.AnswerCount, rp.PostTypes, rp.QuestionPercentage, rp.UserExperienceLevel, rp.ReputationTier, rp.BadgeCount, 
    rp.BadgeNames, rp.ReputationRank, rp.ViewCategory, rp.ReputationCategory, rp.ViewRankByType, rp.GlobalViewRank, 
    rp.TypeViewRank, rp.HighScoreRank, rp.ViewPercentile, rp.ScoreDecile, rp.ViewImpactCategory, rp.ScoreImpactCategory
HAVING 
    COUNT(rap.Id) >= 1
    AND COUNT(CASE WHEN rap.PostStatus = 'Active' THEN 1 END) > 0
    AND COUNT(CASE WHEN rap.Score > 0 THEN 1 END) >= 1
ORDER BY 
    CASE 
        WHEN rp.GlobalViewRank <= 10 THEN 1
        WHEN rp.GlobalViewRank <= 100 THEN 2
        WHEN rp.GlobalViewRank <= 1000 THEN 3
        ELSE 4
    END,
    rp.ViewCount DESC,
    rp.Score DESC
LIMIT 1000;