-- {"query": "29004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1530} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        MAX(p.CreationDate) as LatestPostDate,
        DATEDIFF('DAY', u.CreationDate, CURRENT_TIMESTAMP) as DaysSinceRegistration,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN 1 ELSE 0 END as HasWebsite
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.WebsiteUrl, u.CreationDate
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC) as QuestionRank,
        ROW_NUMBER() OVER (ORDER BY TotalAnswerScore DESC) as AnswerRank,
        PERCENT_RANK() OVER (ORDER BY Reputation) as ReputationPercentile
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question' 
            WHEN p.PostTypeId = 2 THEN 'Answer' 
            ELSE 'Other' 
        END as PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'HighlyVoted'
            WHEN p.Score >= 10 THEN 'ModeratelyVoted'
            WHEN p.Score >= 0 THEN 'Neutral'
            ELSE 'Downvoted'
        END as VoteCategory,
        CASE 
            WHEN p.ViewCount >= 1000 THEN 'Popular'
            WHEN p.ViewCount >= 100 THEN 'Moderate'
            WHEN p.ViewCount >= 10 THEN 'Low'
            ELSE 'VeryLow'
        END as Popularity,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountRecursive,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)) as EditCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.CreationDate >= '2019-01-01'
    AND (p.Title IS NOT NULL AND p.Title != '')
    AND (p.Body IS NOT NULL AND p.Body != '')
),
FinalAnalysis AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPosts,
        ru.Questions,
        ru.Answers,
        ru.Badges,
        ru.TotalQuestionScore,
        ru.TotalAnswerScore,
        ru.ReputationPercentile,
        COUNT(pa.PostId) as AnalyzedPosts,
        AVG(pa.Score) as AvgPostScore,
        MAX(pa.ViewCount) as MaxViewCount,
        SUM(pa.CommentCount) as TotalComments,
        STRING_AGG(DISTINCT SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags)-2), ';') as AllTags,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ru.UserId AND p.Score > 0),
            0
        ) as PositiveScorePosts,
        COALESCE(
            (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph 
             WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ru.UserId)
             AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)),
            0
        ) as EditorCount,
        CASE 
            WHEN ru.Reputation > 10000 THEN 'Elite'
            WHEN ru.Reputation > 1000 THEN 'Expert'
            WHEN ru.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserTier,
        COALESCE(
            (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.UserId = ru.UserId AND v.BountyAmount IS NOT NULL),
            0
        ) as AvgBountyAmount
    FROM RankedUsers ru
    LEFT JOIN PostAnalysis pa ON ru.UserId = pa.OwnerUserId
    WHERE ru.Reputation > 100
    GROUP BY ru.UserId, ru.DisplayName, ru.Reputation, ru.TotalPosts, ru.Questions, ru.Answers, 
             ru.Badges, ru.TotalQuestionScore, ru.TotalAnswerScore, ru.ReputationPercentile
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.TotalPosts,
    fa.Questions,
    fa.Answers,
    fa.Badges,
    fa.TotalQuestionScore,
    fa.TotalAnswerScore,
    fa.ReputationPercentile,
    fa.AnalyzedPosts,
    fa.AvgPostScore,
    fa.MaxViewCount,
    fa.TotalComments,
    fa.AllTags,
    fa.PositiveScorePosts,
    fa.EditorCount,
    fa.UserTier,
    fa.AvgBountyAmount,
    CASE 
        WHEN fa.TotalPosts > 5 THEN 'Active'
        WHEN fa.TotalPosts > 1 THEN 'Moderate'
        ELSE 'Inactive'
    END as ActivityLevel,
    ROUND(
        (CAST(fa.PositiveScorePosts AS FLOAT) / NULLIF(CAST(fa.TotalPosts AS FLOAT), 0)) * 100, 2
    ) as PositiveRatio,
    ROUND(
        (CAST(fa.EditorCount AS FLOAT) / NULLIF(CAST(fa.AnalyzedPosts AS FLOAT), 0)) * 100, 2
    ) as EditRatio,
    CASE 
        WHEN fa.ReputationPercentile > 0.9 THEN 'Top10%'
        WHEN fa.ReputationPercentile > 0.75 THEN 'Top25%'
        WHEN fa.ReputationPercentile > 0.5 THEN 'Top50%'
        ELSE 'BelowMedian'
    END as ReputationStatus
FROM FinalAnalysis fa
WHERE fa.AnalyzedPosts > 0
AND fa.MaxViewCount IS NOT NULL
AND fa.TotalComments IS NOT NULL
AND fa.AllTags IS NOT NULL
AND fa.PositiveRatio IS NOT NULL
AND fa.EditRatio IS NOT NULL
AND fa.ReputationPercentile IS NOT NULL
ORDER BY fa.Reputation DESC
LIMIT 1000;