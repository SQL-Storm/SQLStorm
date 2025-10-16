WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
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
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.PostTypeId = 2 AND p.Score > 0 THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        NTILE(100) OVER (ORDER BY p.Score) AS ScorePercentile,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        FIRST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS FirstScore,
        LAST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= TIMESTAMP '2010-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.PostId) AS PostCount,
        SUM(ps.Score) AS TotalScore,
        AVG(ps.Score) AS AvgScore,
        MAX(ps.CreationDate) AS LastPostDate,
        MIN(ps.CreationDate) AS FirstPostDate,
        CAST(EXTRACT(EPOCH FROM (MAX(ps.CreationDate) - MIN(ps.CreationDate))) / 86400 AS INTEGER) AS ActiveDays,
        COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN ps.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        COUNT(DISTINCT ps.Tags) AS TagCount,
        STRING_AGG(DISTINCT ps.Tags, ', ') AS AllTags,
        STRING_AGG(DISTINCT ps.Title, ', ') AS AllTitles
    FROM Users u
    JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagMetrics AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'High'
            WHEN t.Count > 100 THEN 'Medium'
            WHEN t.Count > 10 THEN 'Low'
            ELSE 'Very Low'
        END AS PopularityLevel,
        AVG(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS AvgQuestionScore,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.ViewCount) AS MaxViewCount,
        MIN(p.LastActivityDate) AS MinActivityDate
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
QuestionStats AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.PostStatus,
        ps.ScoreRank,
        ps.ViewRank,
        ps.ScorePercentile,
        ps.UserPostRank,
        ps.TotalUserPosts,
        ps.AvgUserScore,
        ps.PrevScore,
        ps.NextScore,
        ps.FirstScore,
        ps.LastScore,
        -- split tags into array elements using regexp_split_to_array then unnest for dialects without regexp_split_to_table
        unnest(regexp_split_to_array(ps.Tags, '>[[:space:]]*')) AS TagsArray,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 
                CASE 
                    WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
                    WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.75 THEN 'Medium'
                    ELSE 'Low'
                END
            ELSE 'No Answers'
        END AS AnswerQuality,
        CASE 
            WHEN ps.Tags IS NOT NULL AND LENGTH(ps.Tags) > 0 THEN 
                CASE 
                    WHEN LENGTH(ps.Tags) > 100 THEN 'Long Title'
                    WHEN LENGTH(ps.Tags) > 50 THEN 'Medium Title'
                    ELSE 'Short Title'
                END
            ELSE 'No Tags'
        END AS TitleLength,
        CASE 
            WHEN ps.Score > 100 THEN 10
            WHEN ps.Score > 50 THEN 5
            WHEN ps.Score > 0 THEN 1
            ELSE 0
        END AS EngagementScore
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        ps.PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.PostStatus,
        ps.ScoreRank,
        ps.ViewRank,
        ps.ScorePercentile,
        ps.UserPostRank,
        ps.TotalUserPosts,
        ps.AvgUserScore,
        ps.PrevScore,
        ps.NextScore,
        ps.FirstScore,
        ps.LastScore,
        ps.Title,
        ps.Tags,
        unnest(regexp_split_to_array(ps.Body, '\s+')) AS BodyTokens,
        CASE 
            WHEN ps.Score > 10 THEN 'High Value'
            WHEN ps.Score > 5 THEN 'Medium Value'
            ELSE 'Low Value'
        END AS AnswerValue,
        CASE 
            WHEN ps.LastActivityDate >= TIMESTAMP '2020-01-01' THEN 'Recent'
            WHEN ps.LastActivityDate >= TIMESTAMP '2018-01-01' THEN 'Moderate'
            ELSE 'Old'
        END AS ActivityLevel
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
),
CombinedStats AS (
    SELECT 
        qs.PostId AS QuestionId,
        qs.Title,
        qs.OwnerUserId,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        qs.FavoriteCount,
        qs.CreationDate,
        qs.LastActivityDate,
        qs.PostStatus,
        qs.ScoreRank,
        qs.ViewRank,
        qs.ScorePercentile,
        qs.UserPostRank,
        qs.TotalUserPosts,
        qs.AvgUserScore,
        qs.AnswerQuality,
        qs.TitleLength,
        qs.EngagementScore,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.TotalScore,
        ua.AvgScore,
        ua.LastPostDate,
        ua.FirstPostDate,
        ua.ActiveDays,
        ua.QuestionCount,
        ua.AnswerCount AS UserAnswerCount,
        ua.AllTags,
        ua.AllTitles
    FROM QuestionStats qs
    JOIN UserActivity ua ON qs.OwnerUserId = ua.UserId
),
DetailedPostAnalysis AS (
    SELECT 
        cs.QuestionId,
        cs.Title,
        cs.DisplayName,
        cs.Reputation,
        cs.PostCount,
        cs.TotalScore,
        cs.AvgScore,
        cs.ActiveDays,
        cs.QuestionCount,
        cs.UserAnswerCount,
        cs.Score,
        cs.ViewCount,
        cs.AnswerCount,
        cs.CommentCount,
        cs.FavoriteCount,
        cs.CreationDate,
        cs.LastActivityDate,
        cs.PostStatus,
        cs.ScoreRank,
        cs.ViewRank,
        cs.ScorePercentile,
        cs.UserPostRank,
        cs.TotalUserPosts,
        cs.AvgUserScore,
        cs.AnswerQuality,
        cs.TitleLength,
        cs.EngagementScore,
        CASE 
            WHEN cs.Reputation > 10000 THEN 'Elite'
            WHEN cs.Reputation > 1000 THEN 'Advanced'
            WHEN cs.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS RepLevel,
        CASE 
            WHEN cs.ScorePercentile >= 90 THEN 'Top 10%'
            WHEN cs.ScorePercentile >= 75 THEN 'Top 25%'
            WHEN cs.ScorePercentile >= 50 THEN 'Top 50%'
            ELSE 'Below Average'
        END AS PerformanceTier,
        CASE 
            WHEN cs.AnswerCount > 10 THEN 'Active'
            WHEN cs.AnswerCount > 5 THEN 'Moderate'
            WHEN cs.AnswerCount > 0 THEN 'Minimal'
            ELSE 'No Answers'
        END AS ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY cs.Score DESC) AS Ranking,
        NTILE(4) OVER (ORDER BY cs.Reputation DESC) AS ReputationQuartile,
        LAG(cs.Score) OVER (ORDER BY cs.Score DESC) AS PrevScore,
        LEAD(cs.Score) OVER (ORDER BY cs.Score DESC) AS NextScore,
        CASE 
            WHEN cs.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
                 AND cs.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'High Engagement'
            WHEN cs.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High Quality'
            WHEN cs.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'High Visibility'
            ELSE 'Average'
        END AS QualityIndicator
    FROM CombinedStats cs
)
SELECT 
    dpa.QuestionId,
    dpa.Title,
    dpa.DisplayName,
    dpa.Reputation,
    dpa.PostCount,
    dpa.TotalScore,
    dpa.AvgScore,
    dpa.ActiveDays,
    dpa.QuestionCount,
    dpa.UserAnswerCount,
    dpa.Score,
    dpa.ViewCount,
    dpa.AnswerCount,
    dpa.CommentCount,
    dpa.FavoriteCount,
    dpa.CreationDate,
    dpa.LastActivityDate,
    dpa.PostStatus,
    dpa.ScoreRank,
    dpa.ViewRank,
    dpa.ScorePercentile,
    dpa.UserPostRank,
    dpa.TotalUserPosts,
    dpa.AvgUserScore,
    dpa.AnswerQuality,
    dpa.TitleLength,
    dpa.EngagementScore,
    dpa.RepLevel,
    dpa.PerformanceTier,
    dpa.ActivityLevel,
    dpa.Ranking,
    dpa.ReputationQuartile,
    dpa.PrevScore,
    dpa.NextScore,
    dpa.QualityIndicator,
    CASE 
        WHEN dpa.Score > 100 AND dpa.ViewCount > 1000 THEN 'Viral'
        WHEN dpa.Score > 50 AND dpa.ViewCount > 500 THEN 'Popular'
        WHEN dpa.Score > 20 AND dpa.ViewCount > 100 THEN 'Notable'
        ELSE 'Normal'
    END AS PostCategory,
    CAST(EXTRACT(EPOCH FROM (dpa.LastActivityDate - dpa.CreationDate)) / 86400 AS INTEGER) AS AgeInDays,
    CASE 
        WHEN CAST(EXTRACT(EPOCH FROM (dpa.LastActivityDate - dpa.CreationDate)) / 86400 AS INTEGER) > 365 THEN 'Stale'
        WHEN CAST(EXTRACT(EPOCH FROM (dpa.LastActivityDate - dpa.CreationDate)) / 86400 AS INTEGER) > 90 THEN 'Old'
        WHEN CAST(EXTRACT(EPOCH FROM (dpa.LastActivityDate - dpa.CreationDate)) / 86400 AS INTEGER) > 30 THEN 'Recent'
        ELSE 'Fresh'
    END AS AgeStatus,
    (dpa.Score * 1.0 / NULLIF(dpa.ViewCount, 0)) AS ScoreToViewRatio,
    (dpa.AnswerCount * 1.0 / NULLIF(dpa.ViewCount, 0)) AS AnswerToViewRatio,
    CASE 
        WHEN dpa.UserAnswerCount > dpa.QuestionCount THEN 'More Answers than Questions'
        WHEN dpa.UserAnswerCount = dpa.QuestionCount THEN 'Equal Answers and Questions'
        ELSE 'Fewer Answers than Questions'
    END AS AnswerProfile
FROM DetailedPostAnalysis dpa
WHERE dpa.PerformanceTier IN ('Top 10%', 'Top 25%')
    AND dpa.RepLevel IN ('Elite', 'Advanced')
    AND dpa.ActivityLevel IN ('Active', 'Moderate')
ORDER BY dpa.Score DESC, dpa.ViewCount DESC
LIMIT 1000;