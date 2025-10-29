-- {"query": "7272.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2298} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        COUNT(DISTINCT v.Id) as TotalVotes,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        MAX(v.CreationDate) as LastVoteDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(CAST(p.Score AS FLOAT) / NULLIF(p.ViewCount, 0)) AS DECIMAL(10,4))
            ELSE 0 
        END as AvgScorePerView,
        STRING_AGG(DISTINCT SUBSTRING(p.Title, 1, 50), ', ') as PostTitles,
        STRING_AGG(DISTINCT SUBSTRING(p.Body, 1, 100), ' | ') as PostBodies
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as RankByScoreGlobal,
        NTILE(100) OVER (ORDER BY p.Score DESC) as PercentileRank,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as HasAcceptedAnswer,
        CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END as HasAnswers,
        CASE WHEN p.CommentCount > 0 THEN 1 ELSE 0 END as HasComments
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserPostSummary AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(*) as TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as QuestionsCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as AnswersCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        MAX(p.CreationDate) as LastActivityDate,
        STRING_AGG(p.Title, ' || ') as AllQuestionTitles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' 
            THEN (ARRAY_LENGTH(SPLIT_PART(p.Tags, '><', 2, ARRAY_LENGTH(SPLIT_PART(p.Tags, '><', 1, 1000)), '><') - 1))
            ELSE 0 
        END as TagCount,
        LENGTH(p.Body) as BodyLength,
        SUBSTRING(p.Body, 1, 500) as BodyPreview,
        DATEDIFF('day', p.CreationDate, NOW()) as AgeInDays,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'MildlyVoted'
            ELSE 'LowVoted'
        END as VoteCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'HighTraffic'
            WHEN p.ViewCount > 100 THEN 'ModerateTraffic'
            WHEN p.ViewCount > 10 THEN 'LowTraffic'
            ELSE 'VeryLowTraffic'
        END as TrafficLevel,
        CASE 
            WHEN p.AnswerCount > 5 THEN 'ManyAnswers'
            WHEN p.AnswerCount > 1 THEN 'SomeAnswers'
            WHEN p.AnswerCount = 1 THEN 'OneAnswer'
            ELSE 'NoAnswers'
        END as AnswerLevel
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score IS NOT NULL
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as HistoryCount,
        STRING_AGG(DISTINCT pht.Name, ', ') as HistoryTypes,
        MAX(ph.CreationDate) as LastHistoryDate,
        MIN(ph.CreationDate) as FirstHistoryDate
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostId IS NOT NULL
    GROUP BY ph.PostId
),
AggregateMetrics AS (
    SELECT 
        'Overall' as MetricGroup,
        COUNT(*) as TotalPosts,
        AVG(CAST(Score AS FLOAT)) as AvgScore,
        MAX(CreationDate) as LatestPostDate,
        MIN(CreationDate) as EarliestPostDate
    FROM Posts
    WHERE PostTypeId IN (1, 2)
    UNION ALL
    SELECT 
        'ByCategory' as MetricGroup,
        COUNT(*) as TotalPosts,
        AVG(CAST(Score AS FLOAT)) as AvgScore,
        MAX(CreationDate) as LatestPostDate,
        MIN(CreationDate) as EarliestPostDate
    FROM Posts
    WHERE PostTypeId = 1
    UNION ALL
    SELECT 
        'ByType' as MetricGroup,
        COUNT(*) as TotalPosts,
        AVG(CAST(Score AS FLOAT)) as AvgScore,
        MAX(CreationDate) as LatestPostDate,
        MIN(CreationDate) as EarliestPostDate
    FROM Posts
    WHERE PostTypeId = 2
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalBadges,
    uas.TotalVotes,
    uas.AvgScorePerView,
    uas.PostTitles,
    upsm.AllQuestionTitles,
    CASE 
        WHEN upsm.TotalQuestions > 0 THEN 
            CAST((upsm.AnswersCount * 100.0 / NULLIF(upsm.TotalQuestions, 0)) AS DECIMAL(5,2))
        ELSE 0 
    END as AnswerPercentage,
    CASE 
        WHEN tps.RankByScore <= 3 THEN 
            (SELECT STRING_AGG(CONCAT('(', p.Id, ') ', p.Title), ' | ')
             FROM TopPosts p 
             WHERE p.OwnerUserId = uas.UserId AND p.RankByScore <= 3)
        ELSE NULL 
    END as Top3Questions,
    CASE 
        WHEN EXISTS (SELECT 1 FROM PostAnalysis pa WHERE pa.OwnerUserId = uas.UserId AND pa.VoteCategory = 'HighlyVoted')
        THEN 'HighVoter'
        WHEN EXISTS (SELECT 1 FROM PostAnalysis pa WHERE pa.OwnerUserId = uas.UserId AND pa.VoteCategory = 'ModeratelyVoted')
        THEN 'ModerateVoter'
        ELSE 'LowVoter'
    END as VoterStatus,
    CASE 
        WHEN EXISTS (SELECT 1 FROM PostHistorySummary phs WHERE phs.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = uas.UserId)) 
        THEN STRING_AGG(phs.HistoryTypes, '; ')
        ELSE 'NoHistory'
    END as PostHistoryTypes,
    CASE 
        WHEN uas.LastPostDate > '2023-01-01' AND uas.LastCommentDate > '2023-01-01' THEN 'Active'
        WHEN uas.LastPostDate > '2023-01-01' OR uas.LastCommentDate > '2023-01-01' THEN 'RecentlyActive'
        ELSE 'Inactive'
    END as UserActivityStatus,
    COALESCE(am1.TotalPosts, 0) as TotalQuestions,
    COALESCE(am2.TotalPosts, 0) as TotalAnswers,
    CONCAT('Avg Question Score: ', COALESCE(am3.AvgScore, 0)) as QuestionAvgScore,
    CONCAT('Avg Answer Score: ', COALESCE(am4.AvgScore, 0)) as AnswerAvgScore
FROM UserActivityStats uas
INNER JOIN UserPostSummary upsm ON uas.UserId = upsm.UserId
LEFT JOIN TopPosts tps ON uas.UserId = tps.OwnerUserId AND tps.RankByScore = 1
LEFT JOIN PostHistorySummary phs ON phs.PostId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = uas.UserId
)
LEFT JOIN AggregateMetrics am1 ON am1.MetricGroup = 'ByCategory'
LEFT JOIN AggregateMetrics am2 ON am2.MetricGroup = 'ByType'
LEFT JOIN AggregateMetrics am3 ON am3.MetricGroup = 'ByCategory'
LEFT JOIN AggregateMetrics am4 ON am4.MetricGroup = 'ByType'
WHERE uas.Reputation > 1000
GROUP BY 
    uas.UserId, 
    uas.DisplayName, 
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalBadges,
    uas.TotalVotes,
    uas.AvgScorePerView,
    uas.PostTitles,
    upsm.AllQuestionTitles,
    upsm.TotalQuestions,
    upsm.AnswersCount,
    tps.RankByScore,
    am1.TotalPosts,
    am2.TotalPosts,
    am3.AvgScore,
    am4.AvgScore
HAVING 
    uas.TotalPosts > 5 AND
    (uas.TotalVotes > 0 OR uas.TotalBadges > 0)
ORDER BY 
    uas.Reputation DESC,
    uas.TotalPosts DESC,
    uas.TotalVotes DESC
LIMIT 1000;