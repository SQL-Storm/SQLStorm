-- {"query": "7855.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1954}
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    COUNT(DISTINCT b.Id) as BadgesCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    AVG(CAST(COALESCE(p.ViewCount, 0) AS DOUBLE PRECISION)) as AvgViewCount,
    MAX(p.CreationDate) as LastPostDate,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) as LastQuestionDate,
    MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate END) as LastAnswerDate,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT ph.Id) as HistoryEntries,
    STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), ', ') as AllTags,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) as RankByReputation,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPostCount,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as DenseRankByReputation,
    PERCENT_RANK() OVER (ORDER BY u.Reputation DESC) as PercentileRank,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as NextReputation,
    NTILE(100) OVER (ORDER BY u.Reputation DESC) as ReputationPercentile,
    CASE 
        WHEN u.Reputation >= 10000 THEN 'Elite'
        WHEN u.Reputation >= 5000 THEN 'Expert'
        WHEN u.Reputation >= 1000 THEN 'Advanced'
        WHEN u.Reputation >= 500 THEN 'Intermediate'
        WHEN u.Reputation >= 100 THEN 'Beginner'
        ELSE 'Newbie'
    END as ReputationLevel,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) - 
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3),
        0
    ) as NetVoteScore,
    EXISTS(
        SELECT 1 FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    ) as ActiveInLastYear,
    (
        SELECT p3.Title 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 1 
        ORDER BY p3.Score DESC
        LIMIT 1
    ) as HighestScoringQuestion,
    (
        SELECT p4.Title 
        FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.PostTypeId = 2 
        ORDER BY p4.Score DESC
        LIMIT 1
    ) as HighestScoringAnswer,
    (
        SELECT COUNT(DISTINCT ph2.PostId) 
        FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id 
        AND ph2.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    ) as EditingActivity,
    (
        SELECT COUNT(*) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.PostTypeId = 1 
        AND p5.ClosedDate IS NOT NULL
    ) as ClosedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p6 
        WHERE p6.OwnerUserId = u.Id 
        AND p6.PostTypeId = 2 
        AND p6.AcceptedAnswerId IS NOT NULL
    ) as AcceptedAnswers,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            CAST((COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0) / COUNT(DISTINCT p.Id) AS NUMERIC(5,2))
        ELSE 0 
    END as AnswerPercentage,
    COALESCE(
        (SELECT AVG(CHAR_LENGTH(p7.Body)) FROM Posts p7 WHERE p7.OwnerUserId = u.Id AND p7.PostTypeId = 1),
        0
    ) as AvgQuestionLength,
    COALESCE(
        (SELECT AVG(CHAR_LENGTH(p8.Body)) FROM Posts p8 WHERE p8.OwnerUserId = u.Id AND p8.PostTypeId = 2),
        0
    ) as AvgAnswerLength,
    (
        SELECT COUNT(DISTINCT p9.Id) 
        FROM Posts p9 
        INNER JOIN PostLinks pl ON p9.Id = pl.PostId 
        WHERE p9.OwnerUserId = u.Id 
        AND pl.LinkTypeId = 3
    ) as DuplicateLinks,
    (
        SELECT COUNT(DISTINCT p10.Id) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId = 1 
        AND p10.AnswerCount > 10
    ) as HighAnsweredQuestions,
    (
        SELECT COUNT(DISTINCT p11.Id) 
        FROM Posts p11 
        WHERE p11.OwnerUserId = u.Id 
        AND p11.PostTypeId = 1 
        AND p11.ViewCount > 1000
    ) as HighViewedQuestions,
    (
        SELECT STRING_AGG(DISTINCT t.TagName, ', ') 
        FROM Posts p12 
        INNER JOIN Tags t ON POSITION(t.TagName IN p12.Tags) > 0
        WHERE p12.OwnerUserId = u.Id 
        AND p12.PostTypeId = 1
    ) as UserTags,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph3 
        WHERE ph3.UserId = u.Id 
        AND ph3.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days')
    ) as RecentHistory,
    (
        SELECT COUNT(DISTINCT p13.Id) 
        FROM Posts p13 
        INNER JOIN Comments c2 ON p13.Id = c2.PostId 
        WHERE p13.OwnerUserId = u.Id 
        AND c2.UserId IS NOT NULL
    ) as CommentedOnPosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
WHERE 
    u.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years') 
    AND u.Reputation >= 100
    AND (
        (u.Id % 3 = 0 AND EXISTS(SELECT 1 FROM Posts p1 WHERE p1.OwnerUserId = u.Id AND p1.PostTypeId = 1))
        OR
        (u.Id % 5 = 0 AND EXISTS(SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2))
        OR
        (u.Id % 7 = 0 AND EXISTS(SELECT 1 FROM Badges b1 WHERE b1.UserId = u.Id))
        OR
        (u.Id % 11 = 0 AND u.Reputation > 5000)
    )
    AND u.Id NOT IN (
        SELECT UserId 
        FROM Votes v 
        WHERE v.VoteTypeId = 14 
        AND v.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months')
    )
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation,
    u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) >= 10 
    OR COUNT(DISTINCT b.Id) >= 5
    OR EXISTS(
        SELECT 1 FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 1 
        AND p3.Score > 1000
    )
ORDER BY 
    u.Reputation DESC,
    COUNT(DISTINCT p.Id) DESC,
    COUNT(DISTINCT b.Id) DESC
OFFSET 100 ROWS
FETCH NEXT 50 ROWS ONLY;