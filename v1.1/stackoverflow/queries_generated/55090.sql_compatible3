WITH 
    top_users AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
        FROM Users u
        WHERE u.Reputation > 10000
    ),
    user_badges AS (
        SELECT 
            b.UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze
        FROM Badges b
        GROUP BY b.UserId
    ),
    user_votes AS (
        SELECT 
            v.UserId,
            SUM(CASE 
                    WHEN v.VoteTypeId = 2 THEN 1
                    WHEN v.VoteTypeId = 3 THEN -1
                    ELSE 0
                END) AS net_score
        FROM Votes v
        WHERE v.UserId IS NOT NULL
        GROUP BY v.UserId
    ),
    tag_popularity AS (
        SELECT 
            t.TagName,
            t.Count AS tag_use_count,
            p.Id    AS excerpt_post_id,
            p.Title AS excerpt_title
        FROM Tags t
        LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
        WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
    ),
    recent_questions AS (
        SELECT 
            p.Id,
            p.Title,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.AnswerCount,
            STRING_AGG(pt.Name, ' > ') AS type_path
        FROM Posts p
        JOIN PostTypes pt ON p.PostTypeId = pt.Id
        WHERE p.PostTypeId = 1
          AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')
        GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount
    ),
    closure_reasons AS (
        SELECT 
            ph.PostId,
            -- aggregate close events as text to avoid grouping by json
            STRING_AGG(
                (ph.Comment)::text || '|' || COALESCE(ph.UserId::text, '') || '|' || ph.CreationDate::text,
                ';'
            ) FILTER (WHERE ph.PostHistoryTypeId = 10) AS close_events_text
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    ),
    top_links AS (
        SELECT 
            pl.PostId,
            pl.RelatedPostId,
            lt.Name AS link_type,
            pl.Id AS postlink_id,
            pl.LinkTypeId,
            ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn
        FROM PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    )
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    ub.gold,
    ub.silver,
    ub.bronze,
    uv.net_score,
    tp.TagName,
    tp.tag_use_count,
    rq.Title AS recent_question_title,
    rq.Score AS recent_question_score,
    rq.ViewCount AS recent_question_views,
    rq.AnswerCount AS recent_question_answers,
    cr.close_events_text AS close_events,
    tl.RelatedPostId AS most_recent_linked_post,
    lt2.Name AS most_recent_link_type
FROM top_users tu
LEFT JOIN user_badges ub   ON ub.UserId   = tu.Id
LEFT JOIN user_votes uv    ON uv.UserId   = tu.Id
LEFT JOIN LATERAL (
        SELECT tp.TagName, tp.tag_use_count, tp.excerpt_post_id, tp.excerpt_title
        FROM tag_popularity tp 
        ORDER BY tp.tag_use_count DESC 
        LIMIT 1
    ) tp ON TRUE
LEFT JOIN LATERAL (
        SELECT rq.Id, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.AnswerCount, rq.type_path
        FROM recent_questions rq 
        ORDER BY rq.Score DESC 
        LIMIT 1
    ) rq ON TRUE
LEFT JOIN closure_reasons cr ON cr.PostId = tu.Id
LEFT JOIN top_links tl ON tl.PostId = tu.Id AND tl.rn = 1
LEFT JOIN LinkTypes lt2 ON lt2.Id = tl.LinkTypeId
WHERE tu.rn <= 50
GROUP BY
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    ub.gold,
    ub.silver,
    ub.bronze,
    uv.net_score,
    tp.TagName,
    tp.tag_use_count,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    cr.close_events_text,
    tl.RelatedPostId,
    lt2.Name,
    tu.rn
ORDER BY 
    tu.Reputation DESC,
    ub.gold DESC,
    uv.net_score DESC
LIMIT 100;