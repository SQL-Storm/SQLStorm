-- {"query": "3043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2609} 

WITH
    -- User level aggregates
    user_stats AS (
        SELECT
            u.Id                           AS user_id,
            u.DisplayName,
            u.Reputation,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END), 0) AS up_votes_given,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END), 0) AS down_votes_given,
            COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END)   AS gold_badges,
            COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END)   AS silver_badges,
            COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END)   AS bronze_badges
        FROM Users u
        LEFT JOIN Votes   v ON v.UserId = u.Id
        LEFT JOIN Badges  b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    -- Tag popularity and scoring
    tag_stats AS (
        SELECT
            t.TagName,
            t.Count                               AS tag_use_count,
            COALESCE(SUM(p.ViewCount), 0)         AS total_views,
            COALESCE(SUM(p.Score), 0)             AS total_score,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
        FROM Tags t
        LEFT JOIN Posts p
               ON p.Id = t.ExcerptPostId
               OR p.Id = t.WikiPostId
        GROUP BY t.TagName, t.Count
    ),

    -- Question‑level detailed stats
    question_stats AS (
        SELECT
            q.Id                                    AS post_id,
            q.Title,
            q.CreationDate,
            q.Score,
            q.ViewCount,
            q.AnswerCount,
            q.FavoriteCount,
            q.Tags,
            q.OwnerUserId,
            CASE WHEN q.AcceptedAnswerId IS NULL THEN 0 ELSE 1 END AS has_accepted,
            COUNT(c.Id)                             AS comment_cnt,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END),0) AS up_votes,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END),0) AS down_votes,
            ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId
                               ORDER BY q.Score DESC) AS owner_q_rank
        FROM Posts q
        LEFT JOIN Comments c ON c.PostId = q.Id
        LEFT JOIN Votes    v ON v.PostId = q.Id
        WHERE q.PostTypeId = 1                     -- only questions
        GROUP BY q.Id, q.Title, q.CreationDate, q.Score,
                 q.ViewCount, q.AnswerCount, q.FavoriteCount,
                 q.Tags, q.OwnerUserId, q.AcceptedAnswerId
    ),

    -- Most recent close information per post
    recent_closed AS (
        SELECT
            ph.PostId,
            MAX(ph.CreationDate)                                              AS closed_date,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)      AS close_reason_id
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    ),

    -- Combine everything together
    combined AS (
        SELECT
            qs.post_id,
            qs.Title,
            qs.Score,
            qs.ViewCount,
            qs.AnswerCount,
            qs.FavoriteCount,
            qs.comment_cnt,
            qs.up_votes,
            qs.down_votes,
            us.DisplayName,
            us.Reputation,
            us.gold_badges,
            us.silver_badges,
            us.bronze_badges,
            ts.TagName,
            ts.tag_use_count,
            ts.total_views          AS tag_total_views,
            rc.closed_date,
            crt.Name                AS close_reason_name,
            CASE WHEN qs.has_accepted = 1 THEN 'Accepted' ELSE 'NoAccept' END AS accept_status,
            COALESCE(NULLIF(qs.Tags, ''), '<none>')                           AS tag_list,
            ROW_NUMBER() OVER (ORDER BY qs.Score DESC, qs.ViewCount DESC)   AS global_rank
        FROM question_stats qs
        LEFT JOIN user_stats us       ON us.user_id = qs.OwnerUserId
        LEFT JOIN LATERAL (
            SELECT unnest(string_to_array(
                     substring(qs.Tags, 2, length(qs.Tags)-2), '><')) AS TagName
        ) tlist                     ON TRUE
        LEFT JOIN tag_stats ts      ON ts.TagName = tlist.TagName
        LEFT JOIN recent_closed rc  ON rc.PostId = qs.post_id
        LEFT JOIN CloseReasonTypes crt
               ON crt.Id = rc.close_reason_id::smallint
        WHERE qs.Score > 0
    )

SELECT
    post_id,
    Title,
    Score,
    ViewCount,
    AnswerCount,
    FavoriteCount,
    comment_cnt            AS comment_count,
    up_votes,
    down_votes,
    DisplayName            AS owner_name,
    Reputation,
    gold_badges,
    silver_badges,
    bronze_badges,
    TagName,
    tag_use_count          AS tag_use,
    tag_total_views,
    closed_date,
    close_reason_name,
    accept_status,
    tag_list,
    global_rank
FROM combined
WHERE global_rank <= 100

UNION ALL

SELECT
    NULL                  AS post_id,
    'Aggregated Summary'  AS Title,
    NULL                  AS Score,
    NULL                  AS ViewCount,
    NULL                  AS AnswerCount,
    NULL                  AS FavoriteCount,
    NULL                  AS comment_cnt,
    SUM(up_votes) OVER ()   AS total_up_votes,
    SUM(down_votes) OVER () AS total_down_votes,
    NULL                  AS owner_name,
    NULL                  AS Reputation,
    NULL                  AS gold_badges,
    NULL                  AS silver_badges,
    NULL                  AS bronze_badges,
    NULL                  AS TagName,
    NULL                  AS tag_use,
    NULL                  AS tag_total_views,
    NULL                  AS closed_date,
    NULL                  AS close_reason_name,
    NULL                  AS accept_status,
    NULL                  AS tag_list,
    NULL                  AS global_rank
FROM combined
LIMIT 101;
