-- {"query": "7569.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2554}
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END AS VoteCategory,
        COALESCE(p.Tags, '') AS CleanTags,
        LENGTH(p.Tags) AS TagsLength,
        CASE 
            WHEN p.Tags LIKE '%<java>%' THEN 1
            WHEN p.Tags LIKE '%<python>%' THEN 1
            WHEN p.Tags LIKE '%<c++>%' THEN 1
            ELSE 0
        END AS HasPopularTag,
        CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS INTEGER) AS DaysSinceLastActivity,
        ABS(p.Score - LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate)) AS ScoreDelta,
        NTILE(4) OVER (ORDER BY p.Score) AS QuartileRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS TotalAnswers,
        AVG(ps.Score) AS AvgScore,
        MAX(ps.LastActivityDate) AS LastPostActivity,
        STRING_AGG(ps.Title, '; ') AS UserPostTitles,
        COALESCE(STRING_AGG(ps.Tags, ', '), '') AS AllUserTags,
        CASE 
            WHEN COUNT(*) > 100 THEN 'HighlyActive'
            WHEN COUNT(*) > 50 THEN 'ModeratelyActive'
            WHEN COUNT(*) > 10 THEN 'SlightlyActive'
            ELSE 'Inactive'
        END AS ActivityLevel,
        ROUND(AVG(CAST(ps.Score AS numeric)), 2) AS AvgPostScore,
        COUNT(DISTINCT ps.AnswerCount) AS PostsWithAnswers,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN ps.AnswerCount ELSE 0 END) AS TotalAnswersGiven,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersSubmitted
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'PopularTag'
            WHEN t.Count > 100 THEN 'ModerateTag'
            WHEN t.Count > 10 THEN 'SparseTag'
            ELSE 'RareTag'
        END AS TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count AS PopularityDelta,
        AVG(t.Count) OVER () AS AvgTagCount,
        NTILE(5) OVER (ORDER BY t.Count) AS TagTier
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND LENGTH(t.TagName) > 0
),
PerformanceMetrics AS (
    SELECT 
        ps.Id AS PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.UserPostRank,
        ps.QuartileRank,
        ps.VoteCategory,
        ps.PostTypeDesc,
        ps.HasPopularTag,
        ps.DaysSinceLastActivity,
        ps.ScoreDelta,
        ps.AvgUserScore,
        ps.TotalUserPosts,
        CASE 
            WHEN ps.Score > ps.AvgUserScore THEN 'AboveAverage'
            WHEN ps.Score = ps.AvgUserScore THEN 'Average'
            ELSE 'BelowAverage'
        END AS UserScoreComparison,
        CASE 
            WHEN ps.DaysSinceLastActivity < 30 THEN 'RecentlyActive'
            WHEN ps.DaysSinceLastActivity < 90 THEN 'ModerateActivity'
            WHEN ps.DaysSinceLastActivity < 365 THEN 'Inactive'
            ELSE 'VeryInactive'
        END AS ActivityStatus,
        CASE 
            WHEN ps.AnswerCount > 5 THEN 'HighlyAnswered'
            WHEN ps.AnswerCount > 1 THEN 'ModeratelyAnswered'
            ELSE 'LowAnswered'
        END AS AnswerStatus,
        (ps.Score + ps.ViewCount + ps.AnswerCount + ps.CommentCount) AS CompositeScore,
        (ps.Score * 0.4 + ps.ViewCount * 0.3 + ps.AnswerCount * 0.2 + ps.CommentCount * 0.1) AS WeightedScore,
        CASE 
            WHEN ps.Score > 50 AND ps.ViewCount > 500 THEN 'HighImpact'
            WHEN ps.Score > 25 AND ps.ViewCount > 250 THEN 'MediumImpact'
            WHEN ps.Score > 10 AND ps.ViewCount > 100 THEN 'LowImpact'
            ELSE 'MinimalImpact'
        END AS ImpactLevel,
        ps.LastActivityDate,
        ps.CreationDate
    FROM PostStats ps
)
SELECT 
    pm.PostId,
    pm.OwnerUserId,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.UserPostRank,
    pm.QuartileRank,
    pm.VoteCategory,
    pm.PostTypeDesc,
    pm.HasPopularTag,
    pm.DaysSinceLastActivity,
    pm.ScoreDelta,
    pm.AvgUserScore,
    pm.TotalUserPosts,
    pm.UserScoreComparison,
    pm.ActivityStatus,
    pm.AnswerStatus,
    pm.CompositeScore,
    pm.WeightedScore,
    pm.ImpactLevel,
    ua.DisplayName,
    ua.Reputation,
    ua.Views,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgScore,
    ua.ActivityLevel,
    ta.TagName,
    ta.Count AS TagCount,
    ta.TagPopularity,
    CASE 
        WHEN pm.HasPopularTag = 1 THEN 
            CASE 
                WHEN pm.Score > 100 THEN 'Elite'
                WHEN pm.Score > 50 THEN 'Advanced'
                WHEN pm.Score > 25 THEN 'Intermediate'
                ELSE 'Beginner'
            END
        ELSE 'Regular'
    END AS SkillLevel,
    CASE 
        WHEN pm.DaysSinceLastActivity = 0 THEN 'JustNow'
        WHEN pm.DaysSinceLastActivity < 7 THEN 'ThisWeek'
        WHEN pm.DaysSinceLastActivity < 30 THEN 'ThisMonth'
        WHEN pm.DaysSinceLastActivity < 90 THEN 'ThisQuarter'
        WHEN pm.DaysSinceLastActivity < 365 THEN 'ThisYear'
        ELSE 'Old'
    END AS RecencyLevel,
    COALESCE(CASE 
        WHEN pm.Score > pm.AvgUserScore THEN 'AboveUserAverage' 
        WHEN pm.Score < pm.AvgUserScore THEN 'BelowUserAverage'
        ELSE 'AtUserAverage'
    END, 'NotApplicable') AS ScoreComparison,
    CASE 
        WHEN pm.Score > 100 AND pm.AnswerCount > 10 AND pm.CommentCount > 5 THEN 'ExcellentPost'
        WHEN pm.Score > 50 AND pm.AnswerCount > 5 AND pm.CommentCount > 2 THEN 'GoodPost'
        WHEN pm.Score > 25 AND pm.AnswerCount > 2 THEN 'FairPost'
        ELSE 'BasicPost'
    END AS PostQualityGrade,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = pm.OwnerUserId AND p2.PostTypeId = 1) AS UserQuestionsCount,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = pm.OwnerUserId AND p3.PostTypeId = 2) AS UserAnswersCount,
    (SELECT MAX(p4.Score) FROM Posts p4 WHERE p4.OwnerUserId = pm.OwnerUserId) AS UserMaxScore,
    (SELECT MIN(p5.Score) FROM Posts p5 WHERE p5.OwnerUserId = pm.OwnerUserId) AS UserMinScore,
    EXISTS(SELECT 1 FROM Comments c WHERE c.PostId = pm.PostId AND c.Score > 10) AS HasHighlyVotedComments,
    CASE 
        WHEN pm.AnswerCount > (
            SELECT AVG(p6.AnswerCount) FROM Posts p6 WHERE p6.OwnerUserId = pm.OwnerUserId
        ) THEN 'AboveAverageAnswers'
        ELSE 'BelowAverageAnswers'
    END AS AnswerPerformance,
    CASE 
        WHEN pm.ViewCount BETWEEN 100 AND 500 THEN 'StandardViewRange'
        WHEN pm.ViewCount > 500 THEN 'HighViewRange'
        WHEN pm.ViewCount BETWEEN 10 AND 100 THEN 'LowViewRange'
        ELSE 'MinimalViewRange'
    END AS ViewRange,
    CASE 
        WHEN pm.CompositeScore > (
            SELECT AVG(pm2.CompositeScore) FROM PerformanceMetrics pm2
        ) THEN 'AboveOverallAverage'
        WHEN pm.CompositeScore = (
            SELECT AVG(pm3.CompositeScore) FROM PerformanceMetrics pm3
        ) THEN 'AtOverallAverage'
        ELSE 'BelowOverallAverage'
    END AS OverallPerformance,
    (pm.Score / NULLIF(pm.ViewCount, 0)) AS ScoreToViewsRatio,
    (pm.AnswerCount / NULLIF(pm.ViewCount, 0)) AS AnswersToViewsRatio,
    (pm.CommentCount / NULLIF(pm.ViewCount, 0)) AS CommentsToViewsRatio,
    pm.LastActivityDate,
    pm.CreationDate,
    ROW_NUMBER() OVER (ORDER BY pm.CompositeScore DESC) AS RankByComposite,
    RANK() OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.CompositeScore DESC) AS RankByUser,
    DENSE_RANK() OVER (ORDER BY pm.Score DESC) AS RankByScore
FROM PerformanceMetrics pm
JOIN UserActivity ua ON pm.OwnerUserId = ua.UserId
LEFT JOIN TagAnalysis ta ON pm.HasPopularTag = 1 AND EXISTS (
    SELECT 1 FROM Posts p WHERE p.Id = pm.PostId AND (
        p.Tags LIKE '%' || ta.TagName || '%' OR
        p.Title LIKE '%' || ta.TagName || '%'
    )
)
WHERE (pm.Score IS NOT NULL OR pm.ViewCount IS NOT NULL OR pm.AnswerCount IS NOT NULL)
  AND (ua.DisplayName IS NOT NULL OR ua.Reputation IS NOT NULL)
  AND (ta.TagName IS NOT NULL OR pm.HasPopularTag = 0)
  AND pm.DaysSinceLastActivity IS NOT NULL
  AND pm.WeightedScore IS NOT NULL
  AND (pm.Score > 0 OR pm.ViewCount > 0 OR pm.AnswerCount > 0 OR pm.CommentCount > 0)
GROUP BY
    pm.PostId,
    pm.OwnerUserId,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.UserPostRank,
    pm.QuartileRank,
    pm.VoteCategory,
    pm.PostTypeDesc,
    pm.HasPopularTag,
    pm.DaysSinceLastActivity,
    pm.ScoreDelta,
    pm.AvgUserScore,
    pm.TotalUserPosts,
    pm.UserScoreComparison,
    pm.ActivityStatus,
    pm.AnswerStatus,
    pm.CompositeScore,
    pm.WeightedScore,
    pm.ImpactLevel,
    pm.LastActivityDate,
    pm.CreationDate,
    ua.DisplayName,
    ua.Reputation,
    ua.Views,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgScore,
    ua.ActivityLevel,
    ta.TagName,
    ta.Count,
    ta.TagPopularity
ORDER BY pm.CompositeScore DESC, pm.WeightedScore DESC, pm.Score DESC
LIMIT 10000 OFFSET 0;