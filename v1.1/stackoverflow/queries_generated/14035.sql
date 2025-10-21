-- {"query": "14035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 855}
WITH cte AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.Title, 
        p.Body, 
        p.OwnerUserId, 
        p.ClosedDate, 
        p.CommunityOwnedDate,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN p.ClosedDate 
            WHEN p.CommunityOwnedDate IS NOT NULL THEN p.CommunityOwnedDate
            ELSE p.CreationDate
        END AS post_date,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY 
            CASE 
                WHEN p.ClosedDate IS NOT NULL THEN p.ClosedDate
                WHEN p.CommunityOwnedDate IS NOT NULL THEN p.CommunityOwnedDate
                ELSE p.CreationDate
            END) AS owner_post_rank
    FROM Posts p
),
post_tags AS (
    SELECT 
        p.Id, 
        ARRAY_AGG(DISTINCT t.TagName) AS tags
    FROM Posts p
    JOIN string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS t(TagName) ON TRUE
    GROUP BY p.Id
),
post_comments AS (
    SELECT 
        p.Id, 
        COUNT(c.Id) AS comment_count
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
post_votes AS (
    SELECT 
        p.Id, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
)
SELECT
    cte.Id,
    cte.PostTypeId,
    cte.Title,
    cte.Body,
    cte.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    COALESCE(pt.tags, '{}') AS tags,
    COALESCE(pc.comment_count, 0) AS comment_count,
    COALESCE(pv.upvotes, 0) AS upvotes,
    COALESCE(pv.downvotes, 0) AS downvotes,
    CASE
        WHEN cte.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN cte.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS post_status,
    cte.owner_post_rank
FROM cte
LEFT JOIN Users u ON cte.OwnerUserId = u.Id
LEFT JOIN post_tags pt ON cte.Id = pt.Id
LEFT JOIN post_comments pc ON cte.Id = pc.Id
LEFT JOIN post_votes pv ON cte.Id = pv.Id
ORDER BY cte.post_date DESC
LIMIT 100;
