WITH parsed_tags AS (
    SELECT
        p.Id                                 AS post_id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag_name
    FROM Posts p
    WHERE p.PostTypeId = 1                 -- only questions
      AND p.Tags IS NOT NULL
),
tag_stats AS (
    SELECT
        pt.tag_name,
        pt.post_id,
        pt.title,
        pt.score,
        pt.viewcount,
        pt.creationdate,
        pt.owneruserid,
        COALESCE(u.reputation, 0)                         AS owner_reputation,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pt.post_id AND v.VoteTypeId = 2) AS upvote_cnt,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pt.post_id AND v.VoteTypeId = 3) AS downvote_cnt,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pt.post_id)                     AS comment_cnt,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = pt.post_id AND a.PostTypeId = 2) AS answer_cnt,
        (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = pt.post_id AND a.PostTypeId = 2) AS avg_answer_score,
        (SELECT MAX(b.Date) FROM Badges b WHERE b.UserId = pt.owneruserid)               AS last_badge_date
    FROM parsed_tags pt
    LEFT JOIN Users u ON u.Id = pt.owneruserid
),
ranked_q AS (
    SELECT
        ts.*,
        ROW_NUMBER() OVER (
            PARTITION BY ts.tag_name
            ORDER BY
                (ts.score * LOG(GREATEST(ts.viewcount,1) + 1)
                 + ts.upvote_cnt * 0.5
                 - ts.downvote_cnt * 0.3
                ) DESC
        ) AS rn
    FROM tag_stats ts
),
top_five_per_tag AS (
    SELECT
        r.tag_name,
        r.post_id,
        r.title,
        r.score,
        r.viewcount,
        r.owner_reputation,
        r.upvote_cnt,
        r.downvote_cnt,
        r.comment_cnt,
        r.answer_cnt,
        COALESCE(r.avg_answer_score,0)          AS avg_answer_score,
        r.rn                                    AS rank_within_tag
    FROM ranked_q r
    WHERE r.rn <= 5
),
tag_agg AS (
    SELECT
        t.TagName                                 AS tag_name,
        CAST(NULL AS INTEGER)                      AS post_id,
        CAST(NULL AS VARCHAR(300))                 AS title,
        CAST(NULL AS INTEGER)                      AS score,
        CAST(NULL AS INTEGER)                      AS viewcount,
        CAST(NULL AS INTEGER)                      AS owner_reputation,
        CAST(NULL AS INTEGER)                      AS upvote_cnt,
        CAST(NULL AS INTEGER)                      AS downvote_cnt,
        CAST(NULL AS INTEGER)                      AS comment_cnt,
        COUNT(a.Id)                               AS answer_cnt,
        CAST(NULL AS NUMERIC)                      AS avg_answer_score,
        CAST(NULL AS INTEGER)                      AS rank_within_tag
    FROM Tags t
    LEFT JOIN parsed_tags pt ON pt.tag_name = t.TagName
    LEFT JOIN Posts a        ON a.ParentId = pt.post_id AND a.PostTypeId = 2
    GROUP BY t.TagName
    HAVING COUNT(a.Id) > 10
)
SELECT *
FROM top_five_per_tag
UNION ALL
SELECT *
FROM tag_agg
ORDER BY tag_name, rank_within_tag NULLS LAST;