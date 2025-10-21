-- {"query": "29051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1236} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    COALESCE(MAX(p.CreationDate), '1900-01-01') as LatestPostDate,
    COALESCE(MIN(p.CreationDate), '1900-01-01') as EarliestPostDate,
    COUNT(DISTINCT b.Id) as BadgesCount,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COALESCE(
        AVG(CASE 
            WHEN p.PostTypeId = 1 AND p.ViewCount IS NOT NULL THEN p.ViewCount 
            ELSE NULL 
        END), 0
    ) as AvgQuestionViews,
    COALESCE(
        AVG(CASE 
            WHEN p.PostTypeId = 2 AND p.ViewCount IS NOT NULL THEN p.ViewCount 
            ELSE NULL 
        END), 0
    ) as AvgAnswerViews,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id 
        ELSE NULL 
    END) as AcceptedAnswers,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id 
        ELSE NULL 
    END) as QuestionsWithAnswers,
    STRING_AGG(DISTINCT 
        CASE 
            WHEN p.Tags IS NOT NULL THEN SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)
            ELSE NULL 
        END, 
        ', '
    ) as AllTags,
    COALESCE(
        COUNT(DISTINCT CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id 
            ELSE NULL 
        END), 0
    ) as ClosedQuestions,
    COALESCE(
        COUNT(DISTINCT CASE 
            WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id 
            ELSE NULL 
        END), 0
    ) as CommunityOwnedQuestions,
    COALESCE(
        COUNT(DISTINCT CASE 
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id 
            ELSE NULL 
        END), 0
    ) as AnsweredQuestions,
    100.0 * COALESCE(
        COUNT(DISTINCT CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id 
            ELSE NULL 
        END), 0
    ) / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0) as AcceptanceRate,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as UserRank,
    RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationDenseRank,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as PreviousUserReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as NextUserReputation
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(*) as VoteCount,
        SUM(CASE WHEN VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) as VoteActivity,
        MAX(CreationDate) as LastVoteDate
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
) v ON v.UserId = u.Id
WHERE u.Id IN (
    SELECT DISTINCT u2.Id
    FROM Users u2
    INNER JOIN Posts p2 ON p2.OwnerUserId = u2.Id
    INNER JOIN Comments c ON c.PostId = p2.Id
    LEFT JOIN Votes v2 ON v2.PostId = p2.Id AND v2.UserId = u2.Id
    WHERE p2.CreationDate >= '2020-01-01'
    AND (p2.PostTypeId = 1 OR (p2.PostTypeId = 2 AND p2.ParentId IS NOT NULL))
    AND c.CreationDate >= '2020-01-01'
    AND c.UserId IS NOT NULL
    AND c.UserId != u2.Id
)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND (
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0
    )
ORDER BY 
    COUNT(DISTINCT p.Id) DESC,
    u.Reputation DESC
LIMIT 1000