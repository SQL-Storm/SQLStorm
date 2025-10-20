-- {"query": "25028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1847} 

WITH user_stats AS (
    SELECT 
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS upvote_sum,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_tags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
question_detail AS (
    SELECT 
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.FavoriteCount,
        COALESCE(a.answer_cnt,0)          AS answer_cnt,
        COALESCE(b.badge_cnt,0)           AS badge_cnt,
        COALESCE(c.comment_cnt,0)         AS comment_cnt,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed,
        STRING_AGG(DISTINCT tg.TagName, ',') 
            FILTER (WHERE tg.TagName IS NOT NULL) AS tag_list
    FROM Posts q
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS answer_cnt
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON a.ParentId = q.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS badge_cnt
        FROM Badges
        GROUP BY OwnerUserId
    ) b ON b.OwnerUserId = q.OwnerUserId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS comment_cnt
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = q.Id
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '><' FROM q.Tags), '><')) AS raw_tag
    ) rt ON TRUE
    LEFT JOIN Tags tg ON tg.TagName = rt.raw_tag
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount,
             q.FavoriteCount, a.answer_cnt, b.badge_cnt, c.comment_cnt,
             q.ClosedDate
),
recent_active AS (
    SELECT 
        d.Id,
        d.Title,
        d.Score,
        d.ViewCount,
        d.answer_cnt,
        d.tag_list,
        d.is_closed,
        ROW_NUMBER() OVER (PARTITION BY d.is_closed 
                           ORDER BY d.Score DESC, d.ViewCount DESC) AS activity_rank
    FROM question_detail d
    WHERE d.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT 
    us.rep_rank,
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.question_cnt,
    us.answer_cnt,
    us.upvote_sum,
    tt.TagName            AS top_tag,
    ra.Title,
    ra.Score,
    ra.ViewCount,
    ra.answer_cnt        AS ra_answer_cnt,
    ra.tag_list,
    CASE WHEN ra.is_closed = 1 THEN 'Closed' ELSE 'Open' END AS status
FROM user_stats us
LEFT JOIN top_tags tt      ON tt.tag_rank = 1
LEFT JOIN recent_active ra ON ra.activity_rank = 1
WHERE us.rep_rank <= 100
  AND (us.Reputation IS NOT NULL OR us.question_cnt > 0)
ORDER BY us.rep_rank, ra.Score DESC
UNION ALL
SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM user_stats WHERE rep_rank <= 100);
