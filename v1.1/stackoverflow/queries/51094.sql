WITH top_users AS (
    SELECT u.Id, u.Reputation, u.DisplayName
    FROM Users u
    WHERE u.Reputation >= 10000
    ORDER BY u.Reputation DESC
    LIMIT 100
),
active_posts AS (
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
           p.OwnerUserId, p.Title, p.Tags
    FROM Posts p
    INNER JOIN top_users tu ON p.OwnerUserId = tu.Id
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
      AND p.Score > 0
      AND p.ViewCount > 100
),
-- normalize tags into one row per tag per post using a lateral unnest to avoid set-returning-in-aggregate
post_tags AS (
    SELECT ap.Id AS post_id,
           TRIM(BOTH '"' FROM t.tag) AS tag
    FROM active_posts ap,
    LATERAL (
      SELECT UNNEST(string_to_array(SUBSTRING(ap.Tags FROM 2 FOR LENGTH(ap.Tags) - 2), '"><"')) AS tag
    ) t
),
tag_stats AS (
    SELECT pt.post_id,
           COUNT(DISTINCT pt.tag) AS tag_count,
           STRING_AGG(DISTINCT pt.tag, ', ') AS tag_list
    FROM post_tags pt
    GROUP BY pt.post_id
    HAVING COUNT(DISTINCT pt.tag) >= 3
),
engagement_metrics AS (
    SELECT ap.Id,
           COALESCE(v.upvotes, 0) AS upvotes,
           COALESCE(v.downvotes, 0) AS downvotes,
           COALESCE(v.net_score, 0) AS net_score,
           COALESCE(c.comment_count, 0) AS comment_count,
           COALESCE(l.link_count, 0) AS link_count,
           COALESCE(b.badge_count, 0) AS owner_badges
    FROM active_posts ap
    LEFT JOIN (
        SELECT PostId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 
                       WHEN VoteTypeId = 3 THEN -1 
                       ELSE 0 END) AS net_score
        FROM Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ) v ON ap.Id = v.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS comment_count
        FROM Comments
        WHERE Score >= 0
        GROUP BY PostId
    ) c ON ap.Id = c.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS link_count
        FROM PostLinks
        WHERE LinkTypeId = 1
        GROUP BY PostId
    ) l ON ap.Id = l.PostId
    LEFT JOIN (
        SELECT u.Id AS user_id, COUNT(DISTINCT b.Id) AS badge_count
        FROM Users u
        INNER JOIN Badges b ON u.Id = b.UserId
        WHERE b.Class IN (1, 2)
        GROUP BY u.Id
    ) b ON ap.OwnerUserId = b.user_id
),
post_history_summary AS (
    SELECT ph.PostId,
           COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS edit_count,
           MAX(ph.CreationDate) AS last_edit_date,
           AVG(EXTRACT(EPOCH FROM (ph.CreationDate - ap.CreationDate))/3600.0) AS avg_hours_to_edit
    FROM PostHistory ph
    INNER JOIN active_posts ap ON ph.PostId = ap.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11)
    GROUP BY ph.PostId
),
-- precompute net_score for all posts to reuse in percentile subquery
post_net_scores AS (
    SELECT ap.Id AS post_id,
           COALESCE(v.net_score, 0) AS net_score,
           ap.ViewCount,
           COALESCE(em.comment_count, 0) AS comment_count
    FROM active_posts ap
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS net_score
        FROM Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ) v ON ap.Id = v.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS comment_count
        FROM Comments
        WHERE Score >= 0
        GROUP BY PostId
    ) em ON ap.Id = em.PostId
)
SELECT 
    ap.Id AS post_id,
    ap.Title,
    ap.CreationDate AS post_date,
    ap.Score AS post_score,
    ap.ViewCount,
    ap.AnswerCount,
    ts.tag_count,
    ts.tag_list,
    em.upvotes,
    em.downvotes,
    em.net_score,
    em.comment_count,
    em.link_count,
    em.owner_badges,
    phs.edit_count,
    phs.last_edit_date,
    phs.avg_hours_to_edit,
    tu.DisplayName AS owner_name,
    tu.Reputation AS owner_reputation,
    ROW_NUMBER() OVER (
        PARTITION BY EXTRACT(MONTH FROM ap.CreationDate), EXTRACT(YEAR FROM ap.CreationDate)
        ORDER BY (em.net_score * 0.6 + ap.ViewCount * 0.3 + em.comment_count * 0.1) DESC
    ) AS monthly_rank,
    NTILE(4) OVER (
        ORDER BY em.net_score DESC, ap.ViewCount DESC
    ) AS performance_quartile
FROM active_posts ap
INNER JOIN top_users tu ON ap.OwnerUserId = tu.Id
INNER JOIN tag_stats ts ON ap.Id = ts.post_id
LEFT JOIN engagement_metrics em ON ap.Id = em.Id
LEFT JOIN post_history_summary phs ON ap.Id = phs.PostId
WHERE (em.net_score * 0.6 + ap.ViewCount * 0.3 + em.comment_count * 0.1) > (
    SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY (net_score * 0.6 + ViewCount * 0.3 + comment_count * 0.1))
    FROM post_net_scores
)
ORDER BY 
    (em.net_score * 0.6 + ap.ViewCount * 0.3 + em.comment_count * 0.1) DESC,
    ap.CreationDate DESC
LIMIT 500;