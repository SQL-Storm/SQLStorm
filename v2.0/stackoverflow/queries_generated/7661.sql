-- {"query": "7661.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1812} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) as AvgQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE NULL END) as AvgAnswerViews,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    DATEDIFF(DAY, MIN(p.CreationDate), MAX(p.CreationDate)) as DaysActive,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT v.Id) as TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.Id END) as UpDownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END), 0) as VoteCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 0) as VoteRatio,
    COALESCE(
        (
            SELECT TOP 1 t.TagName 
            FROM Posts p2 
            JOIN STRING_SPLIT(p2.Tags, '>') s ON s.value LIKE '%<%' 
            JOIN Tags t ON t.Id = (SELECT Id FROM Tags WHERE TagName = SUBSTRING(s.value, 2, LEN(s.value) - 2))
            WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
            GROUP BY t.TagName 
            ORDER BY COUNT(*) DESC
        ), 
        'No Tags'
    ) as TopTag,
    
    -- Window function to rank users by reputation within their registration range
    RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    
    -- Correlated subquery for finding users who have answered questions with specific tags
    (
        SELECT COUNT(DISTINCT a.Id)
        FROM Posts a
        JOIN Posts q ON a.ParentId = q.Id
        WHERE a.OwnerUserId = u.Id 
        AND q.Tags LIKE '%<sql>%' 
        AND q.PostTypeId = 1
    ) as SqlAnswerCount,
    
    -- CTE for calculating user activity patterns
    (
        WITH ActivityPatterns AS (
            SELECT 
                u2.Id as UserId,
                DATEPART(YEAR, p2.CreationDate) as Year,
                DATEPART(MONTH, p2.CreationDate) as Month,
                COUNT(p2.Id) as PostsThisMonth,
                AVG(p2.Score) as AvgScoreThisMonth,
                COUNT(CASE WHEN p2.PostTypeId = 1 THEN 1 END) as QuestionsThisMonth,
                COUNT(CASE WHEN p2.PostTypeId = 2 THEN 1 END) as AnswersThisMonth
            FROM Users u2
            JOIN Posts p2 ON u2.Id = p2.OwnerUserId
            WHERE u2.Id = u.Id
            GROUP BY u2.Id, DATEPART(YEAR, p2.CreationDate), DATEPART(MONTH, p2.CreationDate)
        )
        SELECT 
            AVG(PostsThisMonth) as AvgMonthlyPosts,
            MAX(PostsThisMonth) as MaxMonthlyPosts,
            STRING_AGG(CAST(PostsThisMonth as VARCHAR(10)), ', ') as MonthlyPostCounts
        FROM ActivityPatterns
    ) as MonthlyActivityStats,
    
    -- Complex calculation using CASE and NULL logic
    CASE 
        WHEN u.Reputation >= 1000000 THEN 'Legendary'
        WHEN u.Reputation >= 100000 THEN 'Master'
        WHEN u.Reputation >= 10000 THEN 'Expert'
        WHEN u.Reputation >= 1000 THEN 'Intermediate'
        WHEN u.Reputation >= 100 THEN 'Beginner'
        ELSE 'Novice'
    END as ReputationLevel,
    
    -- Set operator combination of different user activity types
    (
        SELECT COUNT(*) 
        FROM (
            SELECT 'Question' as Type, p.Id FROM Posts p JOIN Users u2 ON p.OwnerUserId = u2.Id WHERE u2.Id = u.Id AND p.PostTypeId = 1
            UNION
            SELECT 'Answer' as Type, p.Id FROM Posts p JOIN Users u2 ON p.OwnerUserId = u2.Id WHERE u2.Id = u.Id AND p.PostTypeId = 2
            UNION
            SELECT 'Comment' as Type, c.Id FROM Comments c JOIN Users u2 ON c.UserId = u2.Id WHERE u2.Id = u.Id
        ) x
    ) as CombinedActivityCount,
    
    -- String manipulation and concatentation
    CONCAT(
        'User_', 
        u.Id, 
        '_Reputation_', 
        CAST(u.Reputation as VARCHAR(20)),
        '_Level_', 
        CASE 
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END
    ) as UserIdentifier,
    
    -- Complex predicate with multiple conditions
    CASE 
        WHEN u.Reputation >= 10000 AND u.ViewCount >= 10000 AND u.UpVotes >= 1000 
        THEN 'Highly Active'
        WHEN u.Reputation >= 1000 AND u.ViewCount >= 5000 AND u.UpVotes >= 500 
        THEN 'Active'
        WHEN u.Reputation >= 100 AND u.ViewCount >= 1000 AND u.UpVotes >= 100 
        THEN 'Moderate'
        ELSE 'Inactive'
    END as ActivityStatus
    
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.Id IS NOT NULL
    AND u.Reputation >= 0
    AND (
        (u.Reputation >= 1000 OR u.ViewCount >= 1000 OR u.UpVotes >= 100)
        OR EXISTS (
            SELECT 1 
            FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            AND p2.CreationDate >= DATEADD(MONTH, -6, GETDATE())
        )
    )
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.ViewCount, 
    u.UpVotes, 
    u.DownVotes
HAVING 
    COUNT(DISTINCT p.Id) >= 0
    AND (
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0
        OR COUNT(DISTINCT c.Id) > 0
        OR COUNT(DISTINCT b.Id) > 0
    )
ORDER BY 
    u.Reputation DESC,
    TotalPosts DESC,
    COALESCE(SUM(p.Score), 0) DESC
OFFSET 0 ROWS
FETCH NEXT 100000 ROWS ONLY
OPTION (MAXDOP 1)