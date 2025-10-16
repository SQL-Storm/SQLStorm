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
    /* Split tags like '<sql><postgres>' into rows using iterative approach */
    SELECT qid,
           TRIM(BOTH '<>' FROM tag) AS tag,
           ROW_NUMBER() OVER (PARTITION BY qid ORDER BY tag) AS rn
    FROM (
        SELECT qid,
               CASE WHEN pos2 > 0 THEN SUBSTRING(tags FROM pos1 FOR pos2 - pos1)
                    ELSE SUBSTRING(tags FROM pos1)
               END AS tag
        FROM (
            SELECT qid, tags, pos1, pos2
            FROM (
                SELECT qid, Tags AS tags,
                       2 AS pos1, /* first tag starts at position 2 */
                       (CASE WHEN POSITION('><' IN Tags) = 0 THEN 0 ELSE POSITION('><' IN Tags) + 1 END) AS pos2,
                       1 AS lvl
                FROM question_stats
            ) s0
            UNION ALL
            SELECT qid, tags,
                   CASE WHEN pos_next = 0 THEN NULL ELSE pos_next + 1 END AS pos1,
                   CASE WHEN pos_next = 0 THEN 0 ELSE pos_next2 END AS pos2
            FROM (
                SELECT qid, tags,
                       pos AS pos_prev,
                       pos_rel,
                       CASE WHEN pos_rel = 0 THEN 0 ELSE pos + pos_rel END AS pos_next,
                       CASE WHEN pos_rel = 0 THEN 0 ELSE pos + pos_rel + POSITION('><' IN SUBSTRING(tags FROM pos + pos_rel + 1)) END AS pos_next2,
                       pos,
                       pos_rel
                FROM (
                    SELECT qid, tags,
                           POSITION('><' IN tags) AS pos,
                           CASE 
                             WHEN POSITION('><' IN tags) = 0 THEN 0
                             ELSE POSITION('><' IN SUBSTRING(tags FROM POSITION('><' IN tags) + 1))
                           END AS pos_rel
                    FROM question_stats
                ) x1
            ) s1
        ) s2
        WHERE pos1 IS NOT NULL
    ) t
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
       aq.answer_count    AS AnswerCount,
       aq.avg_answer_score    AS Avg_answer_score,
       aq.upvotes         AS Upvotes,
       aq.downvotes       AS Downvotes,
       aq.popularity_level,
       aq.status,
       us.Reputation,
       us.badge_score,
       COALESCE(bt.gold,0) + COALESCE(bt.silver,0) + COALESCE(bt.bronze,0) AS total_badges,
       COALESCE(bt.gold,0)  AS gold,
       COALESCE(bt.silver,0) AS silver,
       COALESCE(bt.bronze,0) AS bronze,
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
GROUP BY
    aq.qid,
    aq.Title,
    aq.Score,
    aq.ViewCount,
    aq.answer_count,
    aq.avg_answer_score,
    aq.upvotes,
    aq.downvotes,
    aq.popularity_level,
    aq.status,
    us.Reputation,
    us.badge_score,
    bt.gold,
    bt.silver,
    bt.bronze,
    qt.tag,
    qt.rn
ORDER BY aq.Score DESC, aq.qid;