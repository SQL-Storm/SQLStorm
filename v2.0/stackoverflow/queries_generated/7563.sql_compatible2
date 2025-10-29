WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostSequence,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.ViewCount) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextViewCount,
        NTILE(10) OVER (ORDER BY p.Score) AS ScoreDecile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN
                -- convert tags like '<tag1><tag2>' into array by splitting on '><' after trimming leading/trailing angle brackets
                (regexp_split_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><'))
            ELSE
                NULL
        END AS TagArray,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        AVG(COALESCE(p.Score, 0)) AS AvgScore,
        MAX(p.CreationDate) AS LastActivity,
        STRING_AGG(DISTINCT p.Tags, '; ') AS AllTags,
        COUNT(DISTINCT CASE WHEN p.Tags IS NOT NULL THEN p.Id END) AS TaggedPostsCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
PostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ScoreRank,
        rp.UserPostSequence,
        rp.PrevScore,
        rp.NextViewCount,
        rp.ScoreDecile,
        rp.TagArray,
        rp.EngagementCount,
        CASE 
            WHEN rp.AnswerCount > 0 THEN (rp.Score * 1.0) / rp.AnswerCount
            ELSE NULL 
        END AS ScorePerAnswer,
        CASE 
            WHEN rp.EngagementCount > 0 THEN (rp.Score * 1.0) / rp.EngagementCount
            ELSE NULL 
        END AS ScorePerEngagement,
        CASE 
            WHEN rp.PrevScore IS NOT NULL THEN rp.Score - rp.PrevScore
            ELSE NULL 
        END AS ScoreChange,
        CASE 
            WHEN rp.Score > 100 THEN 'High'
            WHEN rp.Score > 50 THEN 'Medium'
            WHEN rp.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END AS ScoreTier,
        CASE 
            WHEN array_length(rp.TagArray, 1) > 0 THEN array_length(rp.TagArray, 1)
            ELSE 0
        END AS TagCount,
        COALESCE(char_length(rp.Title), 0) AS TitleLength,
        EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rp.CreationDate)) AS DaysSinceCreation,
        CASE 
            WHEN EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rp.CreationDate)) > 30 THEN 'Old'
            WHEN EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rp.CreationDate)) > 7 THEN 'Recent'
            ELSE 'Fresh'
        END AS AgeCategory
    FROM RankedPosts rp
),
ComplexCalculations AS (
    SELECT 
        pa.Id,
        pa.PostTypeId,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.Title,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.ScoreRank,
        pa.UserPostSequence,
        pa.PrevScore,
        pa.NextViewCount,
        pa.ScoreDecile,
        pa.TagArray,
        pa.EngagementCount,
        pa.ScorePerAnswer,
        pa.ScorePerEngagement,
        pa.ScoreChange,
        pa.ScoreTier,
        pa.TagCount,
        pa.TitleLength,
        pa.DaysSinceCreation,
        pa.AgeCategory,
        COALESCE(us.TotalPosts, 0) AS UserTotalPosts,
        COALESCE(us.QuestionCount, 0) AS UserQuestionCount,
        COALESCE(us.AnswerCount, 0) AS UserAnswerCount,
        COALESCE(us.TotalScore, 0) AS UserTotalScore,
        COALESCE(us.AvgScore, 0) AS UserAvgScore,
        CASE 
            WHEN COALESCE(us.TotalPosts, 0) > 0 THEN ROUND((COALESCE(us.QuestionCount, 0) * 100.0) / COALESCE(us.TotalPosts, 0), 2)
            ELSE 0 
        END AS QuestionPercentage,
        CASE 
            WHEN COALESCE(us.TotalPosts, 0) > 0 THEN ROUND((COALESCE(us.AnswerCount, 0) * 100.0) / COALESCE(us.TotalPosts, 0), 2)
            ELSE 0 
        END AS AnswerPercentage,
        COALESCE(us.Reputation, 0) AS UserReputation,
        COALESCE(us.TaggedPostsCount, 0) AS UserTaggedPosts
    FROM PostAnalysis pa
    LEFT JOIN UserStats us ON pa.OwnerUserId = us.UserId
),
FilteredResults AS (
    SELECT 
        cc.Id,
        cc.PostTypeId,
        cc.Score,
        cc.ViewCount,
        cc.CreationDate,
        cc.OwnerUserId,
        cc.Title,
        cc.Tags,
        cc.AnswerCount,
        cc.CommentCount,
        cc.FavoriteCount,
        cc.TagCount,
        cc.ScoreTier,
        cc.AgeCategory,
        cc.QuestionPercentage,
        cc.AnswerPercentage,
        cc.UserTotalPosts,
        cc.UserQuestionCount,
        cc.UserAnswerCount,
        cc.UserTotalScore,
        cc.UserAvgScore,
        cc.UserReputation AS Reputation,
        cc.UserTaggedPosts,
        cc.ScoreChange,
        cc.ScorePerAnswer,
        cc.ScorePerEngagement,
        CASE 
            WHEN cc.TagCount > 3 THEN 'Many Tags'
            WHEN cc.TagCount > 1 THEN 'Some Tags'
            ELSE 'Few Tags'
        END AS TagCategory,
        CASE 
            WHEN cc.UserTotalScore > 1000 THEN 'High Scorer'
            WHEN cc.UserTotalScore > 100 THEN 'Medium Scorer'
            ELSE 'Low Scorer'
        END AS UserPerformanceTier,
        CASE 
            WHEN cc.DaysSinceCreation > 1000 THEN 'Very Old'
            WHEN cc.DaysSinceCreation > 365 THEN 'Old'
            ELSE 'Recent'
        END AS PostAgeCategory,
        CASE 
            WHEN cc.ScoreChange > 5 THEN 'Significant Improvement'
            WHEN cc.ScoreChange < -5 THEN 'Significant Decline'
            WHEN cc.ScoreChange > 0 THEN 'Improvement'
            WHEN cc.ScoreChange < 0 THEN 'Decline'
            ELSE 'No Change'
        END AS ScoreChangeCategory,
        ROW_NUMBER() OVER (PARTITION BY cc.PostTypeId, cc.ScoreTier ORDER BY cc.Score DESC) AS TypeScoreRank,
        PERCENT_RANK() OVER (ORDER BY cc.Score) AS ScorePercentile,
        RANK() OVER (ORDER BY cc.UserTotalScore DESC, cc.Score DESC) AS OverallRank,
        cc.DaysSinceCreation AS DaysSinceCreation
    FROM ComplexCalculations cc
    WHERE cc.Score IS NOT NULL 
      AND cc.Score BETWEEN -100 AND 5000
),
FinalQuery AS (
    SELECT 
        fr.Id,
        fr.PostTypeId,
        fr.Score,
        fr.ViewCount,
        fr.CreationDate,
        fr.OwnerUserId,
        fr.Title,
        fr.Tags,
        fr.AnswerCount,
        fr.CommentCount,
        fr.FavoriteCount,
        fr.TagCount,
        fr.ScoreTier,
        fr.AgeCategory,
        fr.TagCategory,
        fr.UserPerformanceTier,
        fr.ScoreChangeCategory,
        fr.ScorePercentile,
        fr.UserTotalScore,
        fr.UserAvgScore,
        fr.Reputation,
        fr.UserTotalPosts,
        fr.QuestionPercentage,
        fr.AnswerPercentage,
        fr.DaysSinceCreation,
        fr.ScorePerAnswer,
        fr.ScorePerEngagement,
        fr.TypeScoreRank,
        fr.OverallRank,
        CASE 
            WHEN fr.Score > 0 AND fr.UserAvgScore > 0 THEN ROUND(fr.Score / fr.UserAvgScore, 2)
            ELSE NULL 
        END AS ScoreToAvgRatio,
        CASE 
            WHEN fr.ViewCount > 0 AND fr.Score > 0 THEN ROUND((fr.Score * 1.0) / fr.ViewCount, 4)
            ELSE NULL 
        END AS ScorePerView,
        CASE 
            WHEN fr.AnswerCount > 0 THEN (fr.CommentCount * 1.0) / fr.AnswerCount
            ELSE NULL 
        END AS CommentsPerAnswer,
        CASE 
            WHEN fr.FavoriteCount > 0 THEN (fr.Score * 1.0) / fr.FavoriteCount
            ELSE NULL 
        END AS ScorePerFavorite,
        CASE 
            WHEN fr.Score > 0 AND fr.ViewCount > 10 THEN 'High Engagement Post'
            WHEN fr.Score > 0 AND fr.ViewCount > 5 THEN 'Medium Engagement Post'
            WHEN fr.Score > 0 THEN 'Low Engagement Post'
            ELSE 'Non-Engaging Post'
        END AS EngagementCategory,
        CASE 
            WHEN fr.PostTypeId = 1 THEN (
                SELECT COUNT(*) 
                FROM Posts p 
                WHERE p.ParentId = fr.Id AND p.PostTypeId = 2
            )
            ELSE 0
        END AS AnswerCountFromSubquery
    FROM FilteredResults fr
    WHERE fr.PostTypeId IN (1, 2) 
      AND fr.UserTotalPosts > 0
      AND fr.Reputation >= 0
)
SELECT 
    Id,
    PostTypeId,
    Score,
    ViewCount,
    CreationDate,
    OwnerUserId,
    Title,
    Tags,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    TagCount,
    ScoreTier,
    AgeCategory,
    TagCategory,
    UserPerformanceTier,
    ScoreChangeCategory,
    ScorePercentile,
    UserTotalScore,
    UserAvgScore,
    Reputation,
    UserTotalPosts,
    QuestionPercentage,
    AnswerPercentage,
    DaysSinceCreation,
    ScorePerAnswer,
    ScorePerEngagement,
    TypeScoreRank,
    OverallRank,
    ScoreToAvgRatio,
    ScorePerView,
    CommentsPerAnswer,
    ScorePerFavorite,
    EngagementCategory,
    AnswerCountFromSubquery
FROM FinalQuery fq
WHERE (Score > (
    SELECT AVG(Score) 
    FROM FinalQuery
) OR Score IS NULL)
   AND (ScorePerView > 0 OR ScorePerView IS NULL)
   AND (TagCount > (
    SELECT AVG(TagCount) 
    FROM FinalQuery
) OR TagCount IS NULL)
   AND (DaysSinceCreation BETWEEN 0 AND (
    SELECT MAX(DaysSinceCreation) 
    FROM FinalQuery
))
   AND (OverallRank BETWEEN 1 AND 50000)
ORDER BY 
    Score DESC,
    ViewCount DESC,
    DaysSinceCreation ASC,
    OverallRank ASC
LIMIT 50000;