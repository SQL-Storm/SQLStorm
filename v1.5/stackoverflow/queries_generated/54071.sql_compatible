WITH posts_q AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END), 0)      AS upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END), 0)      AS downvotes,
        COALESCE(COUNT(c.Id), 0)                                     AS comment_cnt
    FROM Posts p
    LEFT JOIN Votes v     ON v.PostId     = p.Id
    LEFT JOIN Comments c  ON c.PostId     = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '12 months'
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.Tags
),
tagged_posts AS (
    SELECT 
        pq.Id      AS post_id,
        UNNEST(string_to_array(
            SUBSTRING(pq.Tags FROM 2 FOR LENGTH(pq.Tags) - 2),
            '"><'))        AS tag
    FROM posts_q pq
),
user_stats AS (
    SELECT 
        u.Id                         AS user_id,
        u.Reputation,
        COUNT(DISTINCT pq.Id)        AS q_count,
        SUM(pq.Score)                AS sum_score,
        SUM(pq.upvotes)              AS sum_upv,
        SUM(pq.downvotes)            AS sum_downv,
        SUM(pq.comment_cnt)          AS sum_comments,
        STRING_AGG(DISTINCT tp.tag, ', ') AS top_tags
    FROM Users u
    JOIN posts_q pq          ON pq.OwnerUserId = u.Id
    LEFT JOIN tagged_posts tp ON tp.post_id = pq.Id
    GROUP BY u.Id, u.Reputation
    HAVING SUM(pq.Score) > 1000
)
SELECT 
    user_id,
    Reputation,
    q_count,
    sum_score,
    sum_upv,
    sum_downv,
    sum_comments,
    top_tags
FROM user_stats
ORDER BY sum_score DESC
LIMIT 100;