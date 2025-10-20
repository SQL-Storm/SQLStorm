WITH popular_tags AS (
    SELECT t.TagName, COUNT(p.Id) AS post_count
    FROM Tags t
    JOIN Posts p ON (
        -- normalize tags like "<tag1><tag2>" into comma-separated list and search for tag name
        REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><', ','), ' ', '') LIKE '%' || t.TagName || '%'
    )
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),
active_users AS (
    SELECT u.Id, u.Reputation, u.UpVotes
    FROM Users u
    JOIN (
        SELECT OwnerUserId, COUNT(*) AS post_count
        FROM Posts
        WHERE OwnerUserId > 0
          AND PostTypeId IN (1, 2)
          AND CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
        GROUP BY OwnerUserId
        HAVING COUNT(*) >= 10
    ) recent_posts ON u.Id = recent_posts.OwnerUserId
),
user_tag_activity AS (
    SELECT au.Id AS user_id,
           pt.TagName,
           COUNT(p.Id) AS activity_count,
           AVG(p.Score) AS avg_score,
           SUM(COALESCE(p.ViewCount,0)) AS total_views
    FROM active_users au
    JOIN Posts p ON p.OwnerUserId = au.Id AND p.PostTypeId = 1
    JOIN popular_tags pt ON (
        REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><', ','), ' ', '') LIKE '%' || pt.TagName || '%'
    )
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months'
    GROUP BY au.Id, pt.TagName
),
engagement_metrics AS (
    SELECT uta.user_id,
           uta.TagName,
           uta.activity_count,
           uta.avg_score,
           uta.total_views,
           COALESCE(b.gold_count, 0) AS gold_badges,
           COALESCE(b.silver_count, 0) AS silver_badges,
           COALESCE(v.upvote_count, 0) AS received_upvotes,
           COALESCE(c.comment_count, 0) AS comment_activity
    FROM user_tag_activity uta
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_count,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver_count
        FROM Badges
        GROUP BY UserId
    ) b ON uta.user_id = b.UserId
    LEFT JOIN (
        SELECT p2.OwnerUserId AS owner_user_id, COUNT(v.Id) AS upvote_count
        FROM Votes v
        JOIN Posts p2 ON p2.Id = v.PostId
        WHERE v.VoteTypeId = 2
        GROUP BY p2.OwnerUserId
    ) v ON uta.user_id = v.owner_user_id
       AND EXISTS (
           SELECT 1 FROM Posts p3
           WHERE p3.OwnerUserId = uta.user_id
             AND REPLACE(REPLACE(SUBSTRING(p3.Tags FROM 2 FOR CHAR_LENGTH(p3.Tags)-2), '><', ','), ' ', '') LIKE '%' || uta.TagName || '%'
       )
    LEFT JOIN (
        SELECT p.OwnerUserId AS user_id, COUNT(*) AS comment_count, STRING_AGG(DISTINCT COALESCE(NULLIF(p.Tags,''),''), ',') AS tags_sample
        FROM Comments c
        JOIN Posts p ON c.PostId = p.Id
        WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months'
        GROUP BY p.OwnerUserId
    ) c ON uta.user_id = c.user_id
       AND REPLACE(REPLACE(SUBSTRING(COALESCE(c.tags_sample,'' ) FROM 2 FOR CHAR_LENGTH(COALESCE(c.tags_sample,''))-2), '><', ','), ' ', '') LIKE '%' || uta.TagName || '%'
    WHERE uta.activity_count >= 3
),
influencer_ranking AS (
    SELECT em.user_id,
           em.TagName,
           em.activity_count,
           em.avg_score,
           em.total_views,
           em.gold_badges,
           em.silver_badges,
           em.received_upvotes,
           em.comment_activity,
           (em.received_upvotes * 2 + em.total_views / 1000 + em.gold_badges * 50 + COALESCE(em.avg_score,0) * 10 + em.comment_activity) AS influence_score,
           au.Reputation AS user_reputation,
           DENSE_RANK() OVER (
             PARTITION BY em.TagName
             ORDER BY (em.received_upvotes * 2 + em.total_views / 1000 + em.gold_badges * 50 + COALESCE(em.avg_score,0) * 10 + em.comment_activity) DESC
           ) AS tag_rank
    FROM engagement_metrics em
    JOIN active_users au ON em.user_id = au.Id
    WHERE em.total_views > 5000 OR em.received_upvotes > 20
)
SELECT 
    ir.TagName,
    ir.user_id,
    u.DisplayName AS user_name,
    ir.user_reputation,
    ir.activity_count,
    ir.avg_score,
    ir.total_views,
    ir.received_upvotes,
    ir.gold_badges,
    ir.silver_badges,
    ir.comment_activity,
    ROUND(CAST(ir.influence_score AS NUMERIC), 2) AS influence_score,
    ir.tag_rank,
    (
        SELECT STRING_AGG(DISTINCT pt2.Name, ', ')
        FROM PostTypes pt2
        WHERE pt2.Id IN (SELECT DISTINCT p.PostTypeId FROM Posts p WHERE p.OwnerUserId = ir.user_id)
    ) AS post_types,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        JOIN Posts p ON pl.RelatedPostId = p.Id
        WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ir.user_id)
          AND pl.LinkTypeId = 1
    ) AS outbound_links
FROM influencer_ranking ir
JOIN Users u ON ir.user_id = u.Id
WHERE ir.tag_rank <= 5
ORDER BY ir.TagName, ir.influence_score DESC;