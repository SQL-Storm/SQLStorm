-- {"query": "7668.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1556} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0) as AvgQuestionScore,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) as AvgAnswerScore,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT ph.Id) as TotalEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as ModerationActions,
    COALESCE(MAX(p.CreationDate), '1900-01-01') as LastPostDate,
    COALESCE(MAX(ph.CreationDate), '1900-01-01') as LastEditDate,
    COALESCE(MAX(c.CreationDate), '1900-01-01') as LastCommentDate,
    COALESCE(MAX(u.LastAccessDate), '1900-01-01') as LastAccess,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(
                (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id)), 
                2
            )
        ELSE 0 
    END as QuestionPercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(
                (COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id)), 
                2
            )
        ELSE 0 
    END as AnswerPercentage,
    RANK() OVER (ORDER BY SUM(p.Score) DESC) as RankingByScore,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankingByPostCount,
    ROW_NUMBER() OVER (ORDER BY u.CreationDate ASC) as NewbieRank,
    LAG(u.DisplayName) OVER (ORDER BY u.Reputation DESC) as PreviousTopReputationUser,
    LEAD(u.DisplayName) OVER (ORDER BY u.Reputation DESC) as NextTopReputationUser,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
        THEN 'Active' 
        ELSE 'Inactive' 
    END as ActivityStatus,
    IIF(
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) > 0 
        OR COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) > 0 
        OR COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) > 0, 
        'BadgeHolder', 
        'NoBadge'
    ) as BadgeStatus,
    (
        SELECT TOP 1 CONCAT('Question: ', p2.Title, ' (Score: ', p2.Score, ')')
        FROM Posts p2
        WHERE p2.PostTypeId = 1 
        AND p2.OwnerUserId = u.Id
        AND p2.Score = (
            SELECT MAX(p3.Score) 
            FROM Posts p3 
            WHERE p3.PostTypeId = 1 AND p3.OwnerUserId = u.Id
        )
    ) as TopScoringQuestion,
    (
        SELECT TOP 1 CONCAT('Answer: ', p2.Title, ' (Score: ', p2.Score, ')')
        FROM Posts p2
        WHERE p2.PostTypeId = 2 
        AND p2.OwnerUserId = u.Id
        AND p2.Score = (
            SELECT MAX(p3.Score) 
            FROM Posts p3 
            WHERE p3.PostTypeId = 2 AND p3.OwnerUserId = u.Id
        )
    ) as TopScoringAnswer,
    STRING_AGG(DISTINCT COALESCE(p.Tags, ''), ', ') as AllTags,
    STRING_AGG(DISTINCT p.Title, ' | ') as AllTitles,
    COALESCE(
        (
            SELECT COUNT(*) 
            FROM Posts p3 
            JOIN PostLinks pl ON p3.Id = pl.PostId 
            WHERE p3.OwnerUserId = u.Id 
            AND pl.LinkTypeId = 3
        ), 
        0
    ) as DuplicateLinksCount,
    CASE 
        WHEN DATEDIFF(DAY, u.CreationDate, GETDATE()) > 365 
        THEN 'Veteran' 
        WHEN DATEDIFF(DAY, u.CreationDate, GETDATE()) > 180 
        THEN 'SemiVeteran' 
        ELSE 'Newbie' 
    END as AccountAgeCategory
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
WHERE (u.CreationDate >= '2010-01-01' OR u.CreationDate IS NULL)
  AND u.Id IN (
    SELECT DISTINCT UserId 
    FROM Badges 
    WHERE Date >= '2020-01-01'
    UNION 
    SELECT DISTINCT UserId 
    FROM Posts 
    WHERE CreationDate >= '2020-01-01'
    UNION
    SELECT DISTINCT UserId 
    FROM Comments 
    WHERE CreationDate >= '2020-01-01'
  )
  AND u.Reputation > 0
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate,
    u.LastAccessDate
HAVING 
    COUNT(DISTINCT p.Id) >= 5
    AND (
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 1 
        OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 1
    )
    OR COUNT(DISTINCT b.Id) >= 3
ORDER BY 
    SUM(p.Score) DESC,
    COUNT(DISTINCT p.Id) DESC,
    u.Reputation DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;