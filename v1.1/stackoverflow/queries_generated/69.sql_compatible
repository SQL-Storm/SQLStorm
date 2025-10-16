WITH RECURSIVE cte_base AS (
    SELECT 
        p.Id AS post_id,
        p.Title AS post_title,
        COUNT(c.Id) AS comment_count
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title
),
cte_recursive_seed AS (
    -- seed rows for recursive member: expand from base posts to their children without aggregates
    SELECT
        cte_base.post_id,
        cte_base.post_title,
        cte_base.comment_count,
        p.Id AS child_id,
        p.Title AS child_title
    FROM cte_base
    JOIN Posts p ON cte_base.post_id = p.ParentId
    WHERE p.PostTypeId = 2
),
cte_recursive AS (
    -- recursive accumulation: bring in children one level at a time, count comments per child separately (no aggregates in recursive term)
    SELECT
        post_id,
        post_title,
        comment_count,
        child_id,
        child_title
    FROM cte_recursive_seed

    UNION ALL

    SELECT
        r.post_id,
        r.post_title,
        r.comment_count,
        p.Id AS child_id,
        p.Title AS child_title
    FROM cte_recursive r
    JOIN Posts p ON r.child_id = p.ParentId
    WHERE p.PostTypeId = 2
),
cte_child_comments AS (
    -- compute comment counts for all child posts separately
    SELECT
        p.Id AS post_id,
        p.Title AS post_title,
        COUNT(c.Id) AS comment_count
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.Id, p.Title
),
cte_union AS (
    -- combine root posts and all descendant posts with their comment counts
    SELECT post_id, post_title, comment_count FROM cte_base
    UNION ALL
    SELECT cc.post_id, cc.post_title, cc.comment_count
    FROM cte_child_comments cc
    JOIN cte_recursive cr ON cc.post_id = cr.child_id
)
SELECT
    post_id,
    post_title,
    comment_count
FROM cte_union
ORDER BY post_id;