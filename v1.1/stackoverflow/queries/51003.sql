WITH high_reputation_users AS (
    SELECT u.Id AS user_id, u.Reputation, u.CreationDate AS user_creation
    FROM Users u
    WHERE u.Reputation >= 1000
),
active_posts AS (
    SELECT p.Id AS post_id, p.CreationDate AS post_creation, p.Score, p.ViewCount,
           p.OwnerUserId, p.AcceptedAnswerId, p.AnswerCount,
           SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)) AS tag_list
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
      AND p.Score > 0
      AND p.ViewCount > 100
),
user_post_stats AS (
    SELECT hru.user_id, ap.post_id,
           COUNT(DISTINCT v.Id) AS vote_count,
           AVG(v.BountyAmount) AS avg_bounty,
           COUNT(DISTINCT ph.Id) AS edit_count,
           COUNT(DISTINCT c.Id) AS comment_count,
           STRING_AGG(DISTINCT t.TagName, ',') AS user_tags
    FROM high_reputation_users hru
    INNER JOIN active_posts ap ON hru.user_id = ap.OwnerUserId
    LEFT JOIN Votes v ON ap.post_id = v.PostId AND v.VoteTypeId IN (2, 3)
       AND v.CreationDate > ap.post_creation
    LEFT JOIN PostHistory ph ON ap.post_id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
       AND ph.UserId = hru.user_id
    LEFT JOIN Comments c ON ap.post_id = c.PostId AND c.UserId = hru.user_id
    LEFT JOIN PostLinks pl ON ap.post_id = pl.PostId AND pl.LinkTypeId = 1
    LEFT JOIN Posts linked_p ON pl.RelatedPostId = linked_p.Id
    INNER JOIN Tags t ON linked_p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY hru.user_id, ap.post_id
    HAVING COUNT(DISTINCT v.Id) > 5
),
aggregated_stats AS (
    SELECT ups.user_id,
           COUNT(ups.post_id) AS post_count,
           SUM(ups.vote_count) AS total_votes,
           SUM(ups.comment_count) AS total_comments,
           AVG(ups.edit_count) AS avg_edits_per_post,
           STRING_AGG(DISTINCT ups.user_tags, ',') AS all_tags
    FROM user_post_stats ups
    GROUP BY ups.user_id
    HAVING COUNT(ups.post_id) >= 3
),
badge_enriched AS (
    SELECT ags.user_id,
           ags.post_count,
           ags.total_votes,
           ags.total_comments,
           ags.avg_edits_per_post,
           ags.all_tags,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
           STRING_AGG(DISTINCT b.Name, '; ') AS badge_names
    FROM aggregated_stats ags
    LEFT JOIN Badges b ON ags.user_id = b.UserId
    GROUP BY ags.user_id, ags.post_count, ags.total_votes, ags.total_comments,
             ags.avg_edits_per_post, ags.all_tags
)
SELECT be.user_id,
       u.Reputation,
       u.DisplayName,
       be.post_count,
       be.total_votes,
       be.total_comments,
       ROUND(CAST(be.avg_edits_per_post AS NUMERIC), 2) AS avg_edits,
       be.gold_badges,
       be.silver_badges,
       be.bronze_badges,
       be.badge_names,
       CASE
         WHEN be.all_tags IS NULL THEN 0
         WHEN POSITION(',' IN be.all_tags) = 0 THEN 1
         ELSE (
             SELECT COUNT(DISTINCT TRIM(t)) 
             FROM (
               SELECT TRIM(value) AS t
               FROM UNNEST(STRING_TO_ARRAY(be.all_tags, ',')) AS x(value)
             ) sub
         )
       END AS unique_tag_categories
FROM badge_enriched be
INNER JOIN Users u ON be.user_id = u.Id
INNER JOIN high_reputation_users hru ON be.user_id = hru.user_id
WHERE be.total_votes > 50
ORDER BY be.total_votes DESC, u.Reputation DESC
LIMIT 100;