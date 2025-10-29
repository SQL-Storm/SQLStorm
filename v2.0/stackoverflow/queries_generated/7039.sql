-- {"query": "7039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1940} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        TotalViews,
        LatestPostDate,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, AnswerCount DESC) as RankByActivity
    FROM UserStats
),
QuestionMetrics AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        CASE 
            WHEN p.Score > 0 THEN 'HighlyVoted'
            WHEN p.Score > -5 THEN 'Moderate'
            ELSE 'Low'
        END as ScoreCategory,
        DATEDIFF(day, p.CreationDate, NOW()) as AgeInDays,
        CASE 
            WHEN DATEDIFF(day, p.CreationDate, NOW()) <= 30 THEN 'New'
            WHEN DATEDIFF(day, p.CreationDate, NOW()) <= 180 THEN 'Medium'
            ELSE 'Old'
        END as AgeCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.Score > 0),
            0
        ) as PositiveAnswers,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) as UpvotesOnQuestion,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) as DownvotesOnQuestion,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN
                (SELECT COUNT(*) FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag)
            ELSE 0
        END as TagCount
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerQuality AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN a.Score > 10 THEN 'Excellent'
            WHEN a.Score > 5 THEN 'Good'
            WHEN a.Score > 0 THEN 'Average'
            WHEN a.Score = 0 THEN 'Neutral'
            ELSE 'Poor'
        END as QualityLevel,
        DATEDIFF(day, a.CreationDate, NOW()) as AgeInDays,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as RankWithinQuestion,
        (SELECT COUNT(*) FROM Posts p WHERE p.ParentId = a.ParentId AND p.PostTypeId = 2) as TotalAnswersInQuestion,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) as UpvotesOnAnswer
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
CombinedMetrics AS (
    SELECT 
        'Users' as EntityType,
        CAST(tu.UserId as VARCHAR) as EntityId,
        tu.DisplayName as EntityName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        NULL as Score,
        NULL as ViewCount,
        NULL as AnswerCount,
        'User' as Category,
        tu.RankByScore,
        tu.RankByActivity
    FROM TopUsers tu
    WHERE tu.RankByScore <= 100
    
    UNION ALL
    
    SELECT 
        'Questions' as EntityType,
        CAST(qm.QuestionId as VARCHAR) as EntityId,
        qm.Title as EntityName,
        NULL as Reputation,
        NULL as PostCount,
        NULL as CommentCount,
        NULL as BadgeCount,
        qm.Score,
        qm.ViewCount,
        qm.AnswerCount,
        qm.ScoreCategory as Category,
        NULL as RankByScore,
        NULL as RankByActivity
    FROM QuestionMetrics qm
    WHERE qm.QuestionId IN (
        SELECT QuestionId FROM QuestionMetrics 
        WHERE Score > 0 
        ORDER BY Score DESC 
        LIMIT 50
    )
    AND qm.ViewCount > 1000
)
SELECT 
    cm.EntityType,
    cm.EntityId,
    cm.EntityName,
    cm.Reputation,
    cm.PostCount,
    cm.CommentCount,
    cm.BadgeCount,
    cm.Score,
    cm.ViewCount,
    cm.AnswerCount,
    cm.Category,
    cm.RankByScore,
    cm.RankByActivity,
    CASE 
        WHEN cm.EntityType = 'Users' AND cm.RankByScore <= 10 THEN 'TopPerformer'
        WHEN cm.EntityType = 'Users' AND cm.RankByScore BETWEEN 11 AND 50 THEN 'HighPerformer'
        WHEN cm.EntityType = 'Users' AND cm.RankByScore BETWEEN 51 AND 100 THEN 'MidPerformer'
        WHEN cm.EntityType = 'Questions' AND cm.Score > 100 THEN 'HighValue'
        WHEN cm.EntityType = 'Questions' AND cm.ViewCount > 10000 THEN 'Viral'
        ELSE 'Regular'
    END as PerformanceLevel,
    CASE 
        WHEN cm.EntityType = 'Users' THEN 
            CASE 
                WHEN cm.Reputation > 10000 THEN 'Expert'
                WHEN cm.Reputation > 5000 THEN 'Advanced'
                WHEN cm.Reputation > 1000 THEN 'Intermediate'
                WHEN cm.Reputation > 0 THEN 'Beginner'
                ELSE 'NoReputation'
            END
        WHEN cm.EntityType = 'Questions' THEN 
            CASE 
                WHEN cm.ViewCount > 10000 THEN 'Popular'
                WHEN cm.ViewCount > 5000 THEN 'WellKnown'
                WHEN cm.ViewCount > 1000 THEN 'Known'
                ELSE 'Unknown'
            END
    END as StatusLevel,
    (SELECT COUNT(*) FROM CombinedMetrics cm2) as TotalEntities,
    COALESCE(
        (SELECT COUNT(*) FROM QuestionMetrics qm2 WHERE qm2.QuestionId = cm.EntityId::INTEGER AND qm2.Score > 0),
        0
    ) as QuestionUpvotes,
    COALESCE(
        (SELECT COUNT(*) FROM AnswerQuality aq WHERE aq.QuestionId = cm.EntityId::INTEGER AND aq.Score >= 0),
        0
    ) as AnswerCountIncludingZero,
    CASE 
        WHEN cm.EntityType = 'Questions' THEN 
            CONCAT('Title: ', cm.EntityName, ' | Score: ', cm.Score, ' | Views: ', cm.ViewCount)
        WHEN cm.EntityType = 'Users' THEN 
            CONCAT('Name: ', cm.EntityName, ' | Rep: ', cm.Reputation, ' | Posts: ', cm.PostCount)
        ELSE 'N/A'
    END as EntitySummary,
    CASE 
        WHEN cm.EntityType = 'Users' AND cm.RankByScore <= 5 THEN 'Top5User'
        WHEN cm.EntityType = 'Questions' AND cm.Category = 'HighlyVoted' THEN 'MostVoted'
        ELSE 'Standard'
    END as SpecialTags
FROM CombinedMetrics cm
WHERE cm.EntityId IS NOT NULL
ORDER BY 
    CASE WHEN cm.EntityType = 'Users' THEN cm.Reputation ELSE cm.Score END DESC,
    cm.EntityType DESC,
    cm.EntityName ASC
LIMIT 1000;