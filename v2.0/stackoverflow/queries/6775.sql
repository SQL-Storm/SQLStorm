-- {"query": "6775.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 585}
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalTitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN p.Id END) AS TotalBodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN p.Id END) AS TotalCloseVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN p.Id END) AS TotalReopenVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id END) AS TotalDownVotes,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestAccountCreation,
    AVG((EXTRACT(EPOCH FROM u.LastAccessDate) - EXTRACT(EPOCH FROM u.CreationDate)) / 86400.0) AS AvgDaysBetweenAccess,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.ClosedDate IS NOT NULL
    ) AS TotalClosedQuestions,
    (
        SELECT STRING_AGG(tag, ', ')
        FROM (
            SELECT REGEXP_REPLACE(tag_item, '^>|<$', '') AS tag
            FROM (
                SELECT TRIM(t) AS tag_item
                FROM (
                    SELECT value AS t
                    FROM UNNEST(string_to_array(COALESCE(p.Tags, ''), '><')) AS value
                ) AS split_vals
            ) AS trimmed
            WHERE tag_item <> ''
        ) AS tags
    ) AS MostCommonTags,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.PostId = p.Id
    ) AS TotalComments,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS TotalGoldBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, p.Id, p.Tags
HAVING 
    MAX(u.Reputation) > 1000 
    AND AVG((EXTRACT(EPOCH FROM u.LastAccessDate) - EXTRACT(EPOCH FROM u.CreationDate)) / 86400.0) < 30
ORDER BY 
    TotalPosts DESC, TotalUpVotes DESC
LIMIT 100;