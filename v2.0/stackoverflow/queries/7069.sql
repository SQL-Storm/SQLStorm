-- {"query": "7069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1917}
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END), 0) as TotalAnswersGiven,
        COUNT(DISTINCT b.Id) as BadgesCount,
        STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)) END, ', ') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 
            THEN AVG(p.Score) 
            ELSE 0 
        END as AvgScorePerPost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC) as RankByQuestionScore,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as RankByPostCount,
        RANK() OVER (ORDER BY Reputation DESC) as RankByReputation,
        NTILE(10) OVER (ORDER BY TotalViews DESC) as ViewQuartile
    FROM UserPostStats
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.Tags IS NOT NULL AND CHAR_LENGTH(p.Tags) > 50 THEN 'Highly Tagged'
            WHEN p.Tags IS NOT NULL AND CHAR_LENGTH(p.Tags) > 25 THEN 'Moderately Tagged'
            ELSE 'Low Tagged'
        END as TagComplexity,
        CASE 
            WHEN p.AnswerCount > 10 THEN 'Highly Answered'
            WHEN p.AnswerCount > 5 THEN 'Moderately Answered'
            ELSE 'Low Answered'
        END as AnswerComplexity,
        CAST((CAST(COALESCE(p.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') AS timestamp) - CAST(p.CreationDate AS timestamp)) AS interval) as _age_interval,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Scored'
            WHEN p.Score > 50 THEN 'Moderately Scored'
            ELSE 'Low Scored'
        END as ScoreComplexity
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
PostComplexityNormalized AS (
    SELECT
        PostId,
        Title,
        Score,
        ViewCount,
        AnswerCount,
        CommentCount,
        CreationDate,
        OwnerUserId,
        PostTypeId,
        Tags,
        TagComplexity,
        AnswerComplexity,
        CASE 
            WHEN _age_interval IS NULL THEN NULL
            ELSE CAST(EXTRACT(EPOCH FROM _age_interval) / 86400 AS INTEGER)
        END as PostAgeDays,
        ScoreComplexity
    FROM PostComplexity
),
-- compute average days between actions per user in a subquery that uses window functions but does not nest them inside aggregates
UserActionDifferences AS (
    SELECT
        vh.UserId,
        vh.Id as HistoryId,
        vh.CreationDate,
        LAG(vh.CreationDate) OVER (PARTITION BY vh.UserId ORDER BY vh.CreationDate) as PrevCreationDate
    FROM PostHistory vh
    WHERE vh.UserId IS NOT NULL
),
UserActionDiffsComputed AS (
    SELECT
        UserId,
        HistoryId,
        CreationDate,
        PrevCreationDate,
        CASE 
            WHEN PrevCreationDate IS NULL THEN NULL
            ELSE EXTRACT(EPOCH FROM (CreationDate - PrevCreationDate)) / 86400.0
        END as DaysSincePrev
    FROM UserActionDifferences
),
UserActivityPatterns AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT vh.Id) as HistoryActions,
        COUNT(DISTINCT CASE WHEN vh.PostHistoryTypeId IN (1,2,3,4,5,6) THEN vh.Id END) as EditActions,
        COUNT(DISTINCT CASE WHEN vh.PostHistoryTypeId IN (10,11,12,13) THEN vh.Id END) as ModerationActions,
        MAX(vh.CreationDate) as LastActivityDate,
        AVG(uadc.DaysSincePrev) as AvgDaysBetweenActions
    FROM Users u
    LEFT JOIN PostHistory vh ON u.Id = vh.UserId
    LEFT JOIN UserActionDiffsComputed uadc ON vh.UserId = uadc.UserId AND vh.Id = uadc.HistoryId
    GROUP BY u.Id, u.DisplayName
),
CombinedStats AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPosts,
        ru.Questions,
        ru.Answers,
        ru.TotalQuestionScore,
        ru.TotalAnswerScore,
        ru.LastPostDate,
        ru.TotalViews,
        ru.TotalAnswersGiven,
        ru.BadgesCount,
        ru.AvgScorePerPost,
        ru.RankByQuestionScore,
        ru.RankByPostCount,
        ru.RankByReputation,
        ru.ViewQuartile,
        uap.HistoryActions,
        uap.EditActions,
        uap.ModerationActions,
        uap.LastActivityDate,
        uap.AvgDaysBetweenActions,
        pcn.PostId,
        pcn.Title,
        pcn.Score as PostScore,
        pcn.ViewCount as PostViewCount,
        pcn.AnswerCount as PostAnswerCount,
        pcn.CommentCount as PostCommentCount,
        pcn.CreationDate as PostCreationDate,
        pcn.PostTypeId,
        pcn.Tags,
        pcn.TagComplexity,
        pcn.AnswerComplexity,
        pcn.PostAgeDays,
        pcn.ScoreComplexity
    FROM RankedUsers ru
    LEFT JOIN UserActivityPatterns uap ON ru.UserId = uap.UserId
    LEFT JOIN PostComplexityNormalized pcn ON ru.UserId = pcn.OwnerUserId
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.TotalPosts,
    cs.Questions,
    cs.Answers,
    cs.TotalQuestionScore,
    cs.TotalAnswerScore,
    cs.LastPostDate,
    cs.TotalViews,
    cs.TotalAnswersGiven,
    cs.BadgesCount,
    cs.AvgScorePerPost,
    cs.RankByQuestionScore,
    cs.RankByPostCount,
    cs.RankByReputation,
    cs.ViewQuartile,
    cs.HistoryActions,
    cs.EditActions,
    cs.ModerationActions,
    cs.LastActivityDate,
    cs.AvgDaysBetweenActions,
    cs.PostId,
    cs.Title,
    cs.PostScore,
    cs.PostViewCount,
    cs.PostAnswerCount,
    cs.PostCommentCount,
    cs.PostCreationDate,
    cs.PostTypeId,
    cs.Tags,
    cs.TagComplexity,
    cs.AnswerComplexity,
    cs.PostAgeDays,
    cs.ScoreComplexity,
    CASE 
        WHEN cs.Reputation > 10000 THEN 'Elite'
        WHEN cs.Reputation > 5000 THEN 'Expert'
        WHEN cs.Reputation > 1000 THEN 'Advanced'
        ELSE 'Novice'
    END as ReputationTier,
    CASE 
        WHEN cs.TotalPosts > 500 THEN 'Veteran'
        WHEN cs.TotalPosts > 100 THEN 'Experienced'
        WHEN cs.TotalPosts > 10 THEN 'Intermediate'
        ELSE 'Beginner'
    END as PostingExperience,
    CASE
        WHEN cs.HistoryActions > 1000 THEN 'Highly Active'
        WHEN cs.HistoryActions > 100 THEN 'Active'
        WHEN cs.HistoryActions > 10 THEN 'Moderate'
        ELSE 'Low Activity'
    END as ActivityLevel,
    CASE
        WHEN cs.AvgDaysBetweenActions < 30 THEN 'Frequent Contributor'
        WHEN cs.AvgDaysBetweenActions < 90 THEN 'Regular Contributor'
        WHEN cs.AvgDaysBetweenActions < 180 THEN 'Occasional Contributor'
        ELSE 'Infrequent Contributor'
    END as ContributionFrequency,
    COALESCE(
        (cs.TotalQuestionScore + cs.TotalAnswerScore) / NULLIF(cs.TotalPosts, 0), 
        0
    ) as OverallEngagementScore,
    NULLIF(
        (cs.Questions * cs.TotalAnswersGiven) / NULLIF(cs.Answers, 0), 
        0
    ) as QuestionAnswerRatio,
    COALESCE(
        (cs.EditActions * 100.0) / NULLIF(cs.HistoryActions, 0), 
        0
    ) as EditPercentage,
    COALESCE(
        (cs.ModerationActions * 100.0) / NULLIF(cs.HistoryActions, 0), 
        0
    ) as ModerationPercentage
FROM CombinedStats cs
WHERE 
    cs.Reputation > 500 
    AND cs.TotalPosts > 10
    AND (cs.Tags IS NOT NULL OR cs.Tags = '')
    AND (
        (cs.PostId IS NOT NULL AND cs.PostAgeDays < 3650)
        OR (cs.PostId IS NULL AND cs.HistoryActions > 0)
    )
    AND (
        cs.ViewQuartile >= 7
        OR cs.RankByReputation <= 100
        OR cs.RankByQuestionScore <= 50
    )
ORDER BY 
    cs.TotalQuestionScore DESC,
    cs.Reputation DESC,
    cs.TotalPosts DESC,
    cs.LastActivityDate DESC
LIMIT 500;