-- {"query": "29018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2892} 
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
        p.Body,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.PostTypeId = 2 AND p.Score > 0 THEN 'Answered'
            ELSE 'Open'
        END as PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(100) OVER (ORDER BY p.Score) as ScorePercentile,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        FIRST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as FirstScore,
        LAST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as LastScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2010-01-01'
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.PostId) as PostCount,
        SUM(ps.Score) as TotalScore,
        AVG(ps.Score) as AvgScore,
        MAX(ps.CreationDate) as LastPostDate,
        MIN(ps.CreationDate) as FirstPostDate,
        DATEDIFF('day', MIN(ps.CreationDate), MAX(ps.CreationDate)) as ActiveDays,
        COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN ps.PostTypeId = 2 THEN 1 END) as AnswerCount,
        COUNT(DISTINCT ps.Tags) as TagCount,
        STRING_AGG(DISTINCT ps.Tags, ', ') as AllTags,
        STRING_AGG(DISTINCT ps.Title, ', ') as AllTitles
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
        END as PopularityLevel,
        AVG(CASE WHEN ps.Score > 0 THEN ps.Score ELSE 0 END) as AvgQuestionScore,
        COUNT(DISTINCT ps.PostId) as QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.PostId END) as AnswerCount,
        MAX(ps.ViewCount) as MaxViewCount,
        MIN(ps.LastActivityDate) as MinActivityDate
    FROM Tags t
    LEFT JOIN Posts ps ON ps.Tags LIKE '%' || t.TagName || '%'
    WHERE ps.PostTypeId = 1
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
        STRING_SPLIT(ps.Tags, '>') as TagsArray,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 
                CASE 
                    WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
                    WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.75 THEN 'Medium'
                    ELSE 'Low'
                END
            ELSE 'No Answers'
        END as AnswerQuality,
        CASE 
            WHEN ps.Tags IS NOT NULL AND LENGTH(ps.Tags) > 0 THEN 
                CASE 
                    WHEN LENGTH(ps.Tags) > 100 THEN 'Long Title'
                    WHEN LENGTH(ps.Tags) > 50 THEN 'Medium Title'
                    ELSE 'Short Title'
                END
            ELSE 'No Tags'
        END as TitleLength,
        CASE 
            WHEN ps.Score > 100 THEN 10
            WHEN ps.Score > 50 THEN 5
            WHEN ps.Score > 0 THEN 1
            ELSE 0
        END as EngagementScore
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
        STRING_SPLIT(ps.Body, ' ') as BodyTokens,
        CASE 
            WHEN ps.Score > 10 THEN 'High Value'
            WHEN ps.Score > 5 THEN 'Medium Value'
            ELSE 'Low Value'
        END as AnswerValue,
        CASE 
            WHEN ps.LastActivityDate >= '2020-01-01' THEN 'Recent'
            WHEN ps.LastActivityDate >= '2018-01-01' THEN 'Moderate'
            ELSE 'Old'
        END as ActivityLevel
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
),
CombinedStats AS (
    SELECT 
        qs.PostId as QuestionId,
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
        qs.En EngagementScore,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.TotalScore,
        ua.AvgScore,
        ua.LastPostDate,
        ua.FirstPostDate,
        ua.ActiveDays,
        ua.QuestionCount,
        ua.AnswerCount as UserAnswerCount,
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
        cs.En EngagementScore,
        CASE 
            WHEN cs.Reputation > 10000 THEN 'Elite'
            WHEN cs.Reputation > 1000 THEN 'Advanced'
            WHEN cs.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as RepLevel,
        CASE 
            WHEN cs.ScorePercentile >= 90 THEN 'Top 10%'
            WHEN cs.ScorePercentile >= 75 THEN 'Top 25%'
            WHEN cs.ScorePercentile >= 50 THEN 'Top 50%'
            ELSE 'Below Average'
        END as PerformanceTier,
        CASE 
            WHEN cs.AnswerCount > 10 THEN 'Active'
            WHEN cs.AnswerCount > 5 THEN 'Moderate'
            WHEN cs.AnswerCount > 0 THEN 'Minimal'
            ELSE 'No Answers'
        END as ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY cs.Score DESC) as Ranking,
        NTILE(4) OVER (ORDER BY cs.Reputation DESC) as ReputationQuartile,
        LAG(cs.Score) OVER (ORDER BY cs.Score DESC) as PrevScore,
        LEAD(cs.Score) OVER (ORDER BY cs.Score DESC) as NextScore,
        CASE 
            WHEN cs.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
            AND cs.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'High Engagement'
            WHEN cs.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High Quality'
            WHEN cs.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'High Visibility'
            ELSE 'Average'
        END as QualityIndicator
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
    dpa.En EngagementScore,
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
    END as PostCategory,
    DATEDIFF('day', dpa.CreationDate, dpa.LastActivityDate) as AgeInDays,
    CASE 
        WHEN DATEDIFF('day', dpa.CreationDate, dpa.LastActivityDate) > 365 THEN 'Stale'
        WHEN DATEDIFF('day', dpa.CreationDate, dpa.LastActivityDate) > 90 THEN 'Old'
        WHEN DATEDIFF('day', dpa.CreationDate, dpa.LastActivityDate) > 30 THEN 'Recent'
        ELSE 'Fresh'
    END as AgeStatus,
    (dpa.Score * 1.0 / NULLIF(dpa.ViewCount, 0)) as ScoreToViewRatio,
    (dpa.AnswerCount * 1.0 / NULLIF(dpa.ViewCount, 0)) as AnswerToViewRatio,
    CASE 
        WHEN dpa.UserAnswerCount > dpa.QuestionCount THEN 'More Answers than Questions'
        WHEN dpa.UserAnswerCount = dpa.QuestionCount THEN 'Equal Answers and Questions'
        ELSE 'Fewer Answers than Questions'
    END as AnswerProfile
FROM DetailedPostAnalysis dpa
WHERE dpa.PerformanceTier IN ('Top 10%', 'Top 25%')
    AND (dpa.RepLevel = 'Elite' OR dpa.RepLevel = 'Advanced')
    AND dpa.ActivityLevel IN ('Active', 'Moderate')
ORDER BY dpa.Score DESC, dpa.ViewCount DESC
LIMIT 1000;