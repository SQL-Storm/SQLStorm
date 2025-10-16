-- {"query": "15008.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 21015, "output_tokens": 6157} 
WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        COUNT(*) AS TagCount,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank,
        AVG(p.Score) AS AvgTagPostScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    CROSS APPLY string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS t(TagName)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, t.TagName
),
PostInteractions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        COUNT(DISTINCT v.UserId) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COALESCE(
            (SELECT MAX(ph.CreationDate) 
             FROM PostHistory ph 
             WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)),
            p.CreationDate
        ) AS LastEditDate
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score
)
SELECT 
    aut.UserId,
    u.DisplayName,
    aut.TagName,
    aut.TagCount,
    aut.AvgTagPostScore,
    pi.PostId,
    pi.Title,
    pi.Score AS PostScore,
    pi.VoteCount,
    pi.CommentCount,
    CASE 
        WHEN pi.Score > 10 AND pi.VoteCount > 5 THEN 'High Impact'
        WHEN pi.Score > 0 AND pi.VoteCount > 0 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory,
    EXTRACT(YEAR FROM pi.LastEditDate) AS LastEditYear
FROM ActiveUserTags aut
JOIN Users u ON aut.UserId = u.Id
JOIN PostInteractions pi ON u.Id = (
    SELECT p.OwnerUserId 
    FROM Posts p 
    WHERE p.Id = pi.PostId
)
WHERE 
    aut.TagRank <= 3
    AND pi.PostScore > 0
    AND u.Reputation > (
        SELECT AVG(Reputation) 
        FROM Users 
        WHERE Reputation > 0
    )
ORDER BY 
    aut.TagCount DESC, 
    pi.VoteCount DESC
LIMIT 100;