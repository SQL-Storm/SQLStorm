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
    ROUND(COALESCE(AVG(CAST(p.Score AS NUMERIC)), 0), 2) as AvgPostScore,
    MAX(p.LastActivityDate) as LastActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    ) as RecentPostsLastYear,
    (
        SELECT COUNT(*) 
        FROM Votes v2 
        WHERE v2.UserId = u.Id 
        AND v2.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    ) as RecentVotesLastYear,
    (
        SELECT STRING_AGG('Question: ' || pq.Title || ' (Score: ' || pq.Score || ')', '; ')
        FROM (
            SELECT pq_inner.Id, pq_inner.Title, pq_inner.Score, pq_inner.CreationDate, pq_inner.LastActivityDate, pq_inner.LastEditDate, pq_inner.OwnerUserId, pq_inner.PostTypeId
            FROM Posts pq_inner
            INNER JOIN Votes pv ON pq_inner.Id = pv.PostId
            WHERE pq_inner.OwnerUserId = u.Id 
            AND pv.VoteTypeId = 2
            AND pv.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 day')
            GROUP BY pq_inner.Id, pq_inner.Title, pq_inner.Score, pq_inner.CreationDate, pq_inner.LastActivityDate, pq_inner.LastEditDate, pq_inner.OwnerUserId, pq_inner.PostTypeId
            ORDER BY pq_inner.Score DESC
            LIMIT 5
        ) pq
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
            SELECT p3.Title 
            FROM Posts p3 
            WHERE p3.OwnerUserId = u.Id 
            AND p3.PostTypeId = 1
            ORDER BY p3.Score DESC
            LIMIT 1
        ), 
        'No Top Question'
    ) as TopQuestionTitle,
    (
        SELECT COUNT(DISTINCT ph.Id) 
        FROM PostHistory ph 
        INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        WHERE ph.UserId = u.Id 
        AND ph.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 month')
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
        AND p4.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 month')
    ) as ContributionLevel,
    (
        SELECT AVG(EXTRACT(EPOCH FROM (p5.LastEditDate - p5.CreationDate)) / 86400.0) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.LastEditDate IS NOT NULL
    ) as AvgDaysBetweenCreationAndEdit,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.UserId = u.Id 
        AND c.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '4 week')
    ) as RecentComments,
    (
        SELECT STRING_AGG('Tag: ' || t2.TagName || ' Count: ' || t2.Count, '; ')
        FROM (
            SELECT t2.Id, t2.TagName, t2.Count
            FROM Tags t2 
            WHERE t2.Id IN (
                SELECT DISTINCT t3.Id 
                FROM Tags t3 
                INNER JOIN Posts p6 ON p6.Tags LIKE '%' || t3.TagName || '%'
                WHERE p6.OwnerUserId = u.Id
            )
            ORDER BY t2.Count DESC
            LIMIT 3
        ) t2
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
    'UserRank: ' ||
    CAST(dense_rank_val AS VARCHAR) ||
    ' of ' ||
    CAST((SELECT COUNT(*) FROM Users) AS VARCHAR) ||
    ' - ActivityScore: ' ||
    CAST((COUNT(DISTINCT p.Id) + COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) * 2) AS VARCHAR)
    as UserActivitySummary
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN LATERAL (
    SELECT DISTINCT t2.Id, t2.TagName
    FROM Tags t2 
    INNER JOIN Posts p2 ON p2.Tags LIKE '%' || t2.TagName || '%'
    WHERE p2.OwnerUserId = u.Id
) tt ON TRUE
LEFT JOIN Tags t ON t.Id = tt.Id
LEFT JOIN LATERAL (
    SELECT DENSE_RANK() OVER (ORDER BY u2.Reputation DESC) as dense_rank_val
    FROM Users u2
    WHERE u2.Id = u.Id
) dr ON TRUE
WHERE u.Reputation >= 10
GROUP BY u.Id, u.DisplayName, u.Reputation, dr.dense_rank_val
HAVING COUNT(DISTINCT p.Id) >= 1
ORDER BY u.Reputation DESC
OFFSET 0
FETCH NEXT 100 ROWS ONLY;