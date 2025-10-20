-- {"query": "25.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 220} 
WITH cte_post_activity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) AS total_post_edits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (12, 13, 14, 15) THEN 1 ELSE 0 END) AS total_post_closed_reopened,
        COUNT(DISTINCT pl.Id) AS total_post_links,
        COUNT(DISTINCT v.Id) AS total_post_votes
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
)

SELECT
    u.DisplayName,
    u.Reputation,
    u.Location,
    cte.total_post_edits,
    cte.total_post_closed_reopened,
    cte.total_post_links,
    cte.total_post_votes
FROM Users u
LEFT JOIN cte_post_activity cte ON u.Id = cte.OwnerUserId
ORDER BY u.Reputation DESC;