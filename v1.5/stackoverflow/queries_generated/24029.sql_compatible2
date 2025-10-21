WITH question_stats AS (
    SELECT p.Id          AS qid,
           p.Title,
           p.Score,
           p.ViewCount,
           p.Tags,
           p.AcceptedAnswerId,
           p.OwnerUserId,
           (SELECT COUNT(*) FROM Posts a 
              WHERE a.ParentId = p.Id AND a.PostTypeId = 2)                  AS answer_count,
           (SELECT AVG(a.Score) FROM Posts a 
              WHERE a.ParentId = p.Id AND a.PostTypeId = 2)                  AS avg_answer_score,
           (SELECT COUNT(*) FROM Votes v2 
              WHERE v2.PostId = p.Id AND v2.VoteTypeId = 2)                  AS upvotes,
           (SELECT COUNT(*) FROM Votes v3 
              WHERE v3.PostId = p.Id AND v3.VoteTypeId = 3) * -1            AS downvotes,
           CASE WHEN p.Score > 10 THEN 'High' ELSE 'Low' END                  AS popularity_level,
           CASE WHEN p.Score > 0 AND p.ViewCount > 1000 THEN 'Popular' 
                ELSE 'Not' END                                               AS status
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_split AS (
    SELECT qid,
           TRIM('<>' FROM t.tag) AS tag,
           ROW_NUMBER() OVER (PARTITION BY qid ORDER BY t.tag) AS rn
    FROM question_stats q
    CROSS JOIN LATERAL (
        SELECT CAST(value AS VARCHAR) AS tag
        FROM UNNEST(string_to_array(q.Tags, '>')) AS value
    ) AS t
),
by_tag AS (
    SELECT qid, tag, rn
    FROM tag_split
),
ranked_questions AS (
    SELECT qs.*,
           DENSE_RANK() OVER (ORDER BY qs.Score DESC) AS drank
    FROM question_stats qs
),
top_five AS (
    SELECT * FROM ranked_questions WHERE drank <= 5
),
others AS (
    SELECT * FROM ranked_questions WHERE drank > 5
),
all_q AS (
    SELECT * FROM top_five
    UNION ALL
    SELECT * FROM others
),
badge_totals AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
    FROM Badges
    GROUP BY UserId
),
user_stats AS (
    SELECT u.Id   AS uid,
           u.Reputation,
           u.DisplayName,
           COALESCE(b.gold,0) + COALESCE(b.silver,0)*1 + COALESCE(b.bronze,0)*0.5 AS badge_score
    FROM Users u
    LEFT JOIN badge_totals b ON b.UserId = u.Id
)
SELECT aq.qid,
       aq.Title,
       aq.Score,
       aq.ViewCount,
       aq.answer_count AS AnswerCount,
       aq.avg_answer_score AS Avg_answer_score,
       aq.upvotes AS Upvotes,
       aq.downvotes AS Downvotes,
       aq.popularity_level,
       aq.status,
       us.Reputation,
       us.badge_score,
       (bt.gold + bt.silver + bt.bronze) AS total_badges,
       bt.gold,
       bt.silver,
       bt.bronze,
       qt.tag,
       qt.rn
FROM all_q aq
LEFT JOIN user_stats us ON us.uid = aq.OwnerUserId
LEFT JOIN badge_totals bt ON bt.UserId = aq.OwnerUserId
LEFT JOIN (
    SELECT b.qid, b.tag, b.rn
    FROM by_tag b
) qt ON qt.qid = aq.qid
WHERE COALESCE(aq.popularity_level,'Low') <> 'Low'
ORDER BY aq.Score DESC, aq.qid;