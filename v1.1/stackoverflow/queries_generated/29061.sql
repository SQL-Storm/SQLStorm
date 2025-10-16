-- {"query": "29061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1443} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as Wikis,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as UpvotesReceived,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as DownvotesReceived,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    ROUND(COALESCE(AVG(CAST(p.Score AS FLOAT)), 0), 2) as AvgPostScore,
    MAX(p.LastActivityDate) as LastActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    ) as RecentPostsLastYear,
    (
        SELECT COUNT(*) 
        FROM Votes v2 
        WHERE v2.UserId = u.Id 
        AND v2.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    ) as RecentVotesLastYear,
    (
        SELECT STRING_AGG(CONCAT('Question: ', pq.Title, ' (Score: ', pq.Score, ')'), '; ')
        FROM Posts pq 
        INNER JOIN Votes pv ON pq.Id = pv.PostId
        WHERE pq.OwnerUserId = u.Id 
        AND pv.VoteTypeId = 2
        AND pv.CreationDate >= DATEADD(DAY, -30, GETDATE())
        ORDER BY pq.Score DESC
        LIMIT 5
    ) as TopRecentUpvotedQuestions,
    CASE 
        WHEN u.Reputation >= 1000000 THEN 'Legendary'
        WHEN u.Reputation >= 100000 THEN 'Master'
        WHEN u.Reputation >= 10000 THEN 'Expert'
        WHEN u.Reputation >= 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationTier,
    COALESCE(
        (
            SELECT TOP 1 p3.Title 
            FROM Posts p3 
            WHERE p3.OwnerUserId = u.Id 
            AND p3.PostTypeId = 1
            ORDER BY p3.Score DESC
        ), 
        'No Top Question'
    ) as TopQuestionTitle,
    (
        SELECT COUNT(DISTINCT ph.Id) 
        FROM PostHistory ph 
        INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        WHERE ph.UserId = u.Id 
        AND ph.CreationDate >= DATEADD(MONTH, -6, GETDATE())
        AND pht.Name IN ('Edit Title', 'Edit Body', 'Edit Tags', 'Suggested Edit Applied')
    ) as RecentEdits,
    (
        SELECT COUNT(DISTINCT pl.Id) 
        FROM PostLinks pl 
        WHERE pl.PostId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
        )
    ) as LinkedQuestions,
    (
        SELECT 
            CASE 
                WHEN COUNT(*) >= 10 THEN 'Active Contributor'
                WHEN COUNT(*) >= 5 THEN 'Regular Contributor'
                ELSE 'Occasional Contributor'
            END
        FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.CreationDate >= DATEADD(MONTH, -3, GETDATE())
    ) as ContributionLevel,
    (
        SELECT AVG(DATEDIFF(DAY, p5.CreationDate, p5.LastEditDate)) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.LastEditDate IS NOT NULL
    ) as AvgDaysBetweenCreationAndEdit,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.UserId = u.Id 
        AND c.CreationDate >= DATEADD(WEEK, -4, GETDATE())
    ) as RecentComments,
    (
        SELECT STRING_AGG(CONCAT('Tag: ', t2.TagName, ' Count: ', t2.Count), '; ')
        FROM Tags t2 
        WHERE t2.Id IN (
            SELECT DISTINCT t3.Id 
            FROM Tags t3 
            INNER JOIN Posts p6 ON p6.Tags LIKE '%' + t3.TagName + '%'
            WHERE p6.OwnerUserId = u.Id
        )
        ORDER BY t2.Count DESC
        LIMIT 3
    ) as TopTagUsage,
    (
        SELECT COUNT(DISTINCT p7.Id) 
        FROM Posts p7 
        WHERE p7.OwnerUserId = u.Id 
        AND p7.Score > 100
        AND p7.PostTypeId = 1
    ) as HighScoringQuestions,
    (
        SELECT COUNT(DISTINCT p8.Id) 
        FROM Posts p8 
        WHERE p8.OwnerUserId = u.Id 
        AND p8.Score > 100
        AND p8.PostTypeId = 2
    ) as HighScoringAnswers,
    (
        SELECT CONCAT(
            'UserRank: ', 
            DENSE_RANK() OVER (ORDER BY u.Reputation DESC),
            ' of ',
            (SELECT COUNT(*) FROM Users),
            ' - ActivityScore: ',
            (COUNT(DISTINCT p.Id) + COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) * 2)
        ) 
    ) as UserActivitySummary
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Tags t ON t.Id IN (
    SELECT DISTINCT t2.Id 
    FROM Tags t2 
    INNER JOIN Posts p2 ON p2.Tags LIKE '%' + t2.TagName + '%'
    WHERE p2.OwnerUserId = u.Id
)
WHERE u.Reputation >= 10
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) >= 1
ORDER BY u.Reputation DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;