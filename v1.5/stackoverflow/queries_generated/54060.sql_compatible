WITH exploded AS (
    SELECT p.Id AS post_id,
           regexp_split_to_table(
               regexp_replace(p.Tags, '(^<)|(>$)','', 'g'),
               '><'
           ) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
), first_answers AS (
    SELECT ParentId,
           MIN(CreationDate) AS first_ans_date
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
), tag_stats AS (
    SELECT e.tag,
           COUNT(p.Id)                                      AS q_count,
           AVG(p.Score)                                     AS avg_score,
           AVG(EXTRACT(EPOCH FROM (fa.first_ans_date - p.CreationDate))) AS avg_first_answer_secs,
           AVG(p.CommentCount)                              AS avg_comments,
           AVG(p.ViewCount)                                 AS avg_views,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS total_upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS total_downvotes,
           (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) * 1.0) /
           NULLIF(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) * 1.0, 0) AS up_down_ratio
    FROM exploded e
    JOIN Posts p ON e.post_id = p.Id
    LEFT JOIN first_answers fa ON fa.ParentId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY e.tag
), top_users AS (
    SELECT u.Id          AS uid,
           u.Reputation,
           u.DisplayName,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
)
SELECT ts.tag,
       ts.q_count,
       ts.avg_score,
       ts.avg_first_answer_secs,
       ts.avg_comments,
       ts.avg_views,
       ts.total_upvotes,
       ts.total_downvotes,
       ts.up_down_ratio,
       t.Reputation   AS top_user_rep,
       t.DisplayName  AS top_user_name
FROM tag_stats ts
JOIN top_users t
  ON t.rn = 1
ORDER BY ts.avg_first_answer_secs ASC,
         ts.avg_score DESC
LIMIT 20;