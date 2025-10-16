-- {"query": "29028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1813} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        AVG(p.Score) as AvgPostScore,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) as PositiveScoreCount,
        SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) as NegativeScoreCount,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.CreationDate >= DATEADD(day, -30, GETDATE())) as RecentPostsLast30Days
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        AVG(p.Score) as AvgScore,
        COUNT(DISTINCT p.OwnerUserId) as UserCount,
        RANK() OVER (ORDER BY t.Count DESC) as TagRank,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TagUsers
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    INNER JOIN Users u ON u.Id = p.OwnerUserId
    WHERE t.Count > 10 
    GROUP BY t.TagName, t.Count
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysActive,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                CAST(p.AnswerCount AS FLOAT) / NULLIF((p.AnswerCount + p.CommentCount), 0)
            ELSE NULL 
        END as AnswerToCommentRatio,
        CASE 
            WHEN p.OwnerUserId IS NOT NULL AND p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0 
        END as HasAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as TopQuestionByUser,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        CASE 
            WHEN a.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'AboveAverage'
            WHEN a.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'BelowAverage'
            ELSE 'Average' 
        END as ScoreCategory
    FROM Posts a
    WHERE a.PostTypeId = 2
),
UserPostStats AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.Questions,
        ua.Answers,
        ua.Comments,
        ua.Badges,
        ua.LastPostDate,
        ua.ReputationRank,
        ua.AvgPostScore,
        ua.PositiveScoreCount,
        ua.NegativeScoreCount,
        ua.RecentPostsLast30Days,
        CASE 
            WHEN ua.RecentPostsLast30Days > 50 THEN 'HighlyActive'
            WHEN ua.RecentPostsLast30Days > 20 THEN 'ModeratelyActive'
            WHEN ua.RecentPostsLast30Days > 5 THEN 'OccasionallyActive'
            ELSE 'Inactive' 
        END as ActivityLevel,
        CASE 
            WHEN ua.Answers > 0 AND ua.Questions > 0 THEN 
                CAST(ua.Answers AS FLOAT) / NULLIF(ua.Questions, 0)
            ELSE NULL 
        END as AnswerToQuestionRatio,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ua.AvgPostScore) OVER () as MedianAvgScore,
        ROW_NUMBER() OVER (ORDER BY ua.AvgPostScore DESC) as AvgScoreRank
    FROM UserActivityStats ua
    WHERE ua.TotalPosts > 0
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.Comments,
    ups.Badges,
    ups.LastPostDate,
    ups.ReputationRank,
    ups.AvgPostScore,
    ups.PositiveScoreCount,
    ups.NegativeScoreCount,
    ups.RecentPostsLast30Days,
    ups.ActivityLevel,
    ups.AnswerToQuestionRatio,
    ups.AvgScoreRank,
    ts.TagName,
    ts.TagCount,
    ts.AvgScore as TagAvgScore,
    ts.UserCount,
    ts.TagRank,
    ts.TagUsers,
    qs.QuestionId,
    qs.Title,
    qs.Score as QuestionScore,
    qs.ViewCount,
    qs.AnswerCount,
    qs.CommentCount,
    qs.DaysActive,
    qs.AnswerToCommentRatio,
    qs.HasAcceptedAnswer,
    qs.TopQuestionByUser,
    qs.PreviousScore,
    qs.ScorePercentile,
    asa.AnswerId,
    asa.ParentId,
    asa.Score as AnswerScore,
    asa.ScoreCategory,
    CASE 
        WHEN ups.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'AboveAverageReputation'
        ELSE 'BelowAverageReputation'
    END as ReputationLevel,
    CASE 
        WHEN ups.Answers > (SELECT AVG(Answers) FROM UserPostStats) THEN 'AboveAverageAnswerer'
        ELSE 'BelowAverageAnswerer'
    END as AnsweringLevel,
    CASE 
        WHEN ups.PositiveScoreCount > ups.NegativeScoreCount THEN 'PositiveContributor'
        WHEN ups.NegativeScoreCount > ups.PositiveScoreCount THEN 'NegativeContributor'
        ELSE 'NeutralContributor'
    END as ContributionType,
    ISNULL(ts.TagName, 'No Tags') as TagFocus,
    CASE 
        WHEN qs.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'HighValueQuestion'
        WHEN qs.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'LowValueQuestion'
        ELSE 'AverageValueQuestion'
    END as QuestionValueCategory,
    (ups.PositiveScoreCount + ups.NegativeScoreCount) as TotalScoreContributions,
    DENSE_RANK() OVER (ORDER BY (ups.PositiveScoreCount + ups.NegativeScoreCount) DESC) as ContributionRank,
    COALESCE(ups.Reputation, 0) + COALESCE(ups.Badges, 0) + COALESCE(ups.Answers, 0) as CompositeScore
FROM UserPostStats ups
FULL OUTER JOIN TopTags ts ON ts.TagRank <= 10
FULL OUTER JOIN QuestionStats qs ON qs.OwnerUserId = ups.UserId
FULL OUTER JOIN AnswerStats asa ON asa.ParentId = qs.QuestionId
WHERE ups.Reputation > 200
AND (
    (ups.RecentPostsLast30Days > 5 OR ups.Answers > 0 OR ups.Questions > 0) 
    OR ts.TagName IS NOT NULL
)
AND (
    (ups.Answers > 0 AND ups.Questions > 0) 
    OR qs.QuestionId IS NOT NULL
    OR asa.AnswerId IS NOT NULL
)
AND (ups.ActivityLevel IN ('HighlyActive', 'ModeratelyActive') OR ts.TagName IS NOT NULL)
ORDER BY ups.Reputation DESC, ups.TotalPosts DESC, qs.Score DESC, ups.AverageScore DESC
OFFSET 0 ROWS FETCH NEXT 500 ROWS ONLY;