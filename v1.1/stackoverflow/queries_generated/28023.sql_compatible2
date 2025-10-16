WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT b.Id) AS BadgeCount,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.CreationDate BETWEEN DATE '2010-01-01' AND DATE '2020-12-31'
    GROUP BY u.Id, u.DisplayName, u.Reputation
), PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(STRING_AGG(REPLACE(REPLACE(pt.TagName, '<', ''), '>', ''), ', '), 'No Tags') AS FormattedTags,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10, 11)) AS ClosureEvents,
        (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.Id <> p.Id) AS AvgUserPostScore
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')) AS tag
    ) AS t ON TRUE
    LEFT JOIN Tags pt ON pt.TagName = t.tag
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
    WHERE p.PostTypeId = 1 AND p.CreationDate < DATE '2023-01-01'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.AnswerCount, p.CommentCount
)
SELECT 
    au.DisplayName,
    au.ReputationRank,
    ps.PostId,
    ps.FormattedTags,
    ps.ClosureEvents,
    ps.AvgUserPostScore,
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBounty
FROM ActiveUsers au
LEFT JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN Comments c ON ps.PostId = c.PostId AND c.Score > 0
LEFT JOIN Votes v ON ps.PostId = v.PostId
WHERE au.Reputation > 1000
    AND (ps.AnswerCount > 5 OR ps.CommentCount IS NULL)
    AND (ps.FormattedTags LIKE '%sql%' OR ps.FormattedTags = 'No Tags')
GROUP BY au.DisplayName, au.ReputationRank, ps.PostId, ps.FormattedTags, ps.ClosureEvents, ps.AvgUserPostScore
HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 10

UNION ALL

SELECT 
    'Community Wiki' AS DisplayName,
    NULL AS ReputationRank,
    p.Id AS PostId,
    COALESCE(STRING_AGG(REPLACE(REPLACE(pt.TagName, '<', ''), '>', ''), ', '), 'No Tags') AS FormattedTags,
    COUNT(ph.Id) AS ClosureEvents,
    NULL AS AvgUserPostScore,
    0 AS CommentCount,
    0 AS Upvotes,
    0 AS TotalBounty
FROM Posts p
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')) AS tag
) AS tags_unnest ON TRUE
LEFT JOIN Tags pt ON pt.TagName = tags_unnest.tag
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11)
WHERE p.OwnerUserId = -1 AND p.CommunityOwnedDate IS NOT NULL
GROUP BY p.Id
ORDER BY ReputationRank NULLS LAST, Upvotes DESC;