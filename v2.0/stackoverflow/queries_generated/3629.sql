-- {"query": "3629.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1536} 

WITH recent_posts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
user_post_stats AS (
    SELECT
        u.Id        AS user_id,
        COUNT(rp.Id)                     AS post_count,
        AVG(rp.Score)                    AS avg_score,
        SUM(CASE WHEN rp.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END) AS sql_tag_posts
    FROM Users u
    LEFT JOIN recent_posts rp
        ON rp.OwnerUserId = u.Id
    GROUP BY u.Id
),
recent_badges AS (
    SELECT
        b.UserId,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS recent_badge_list
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY b.UserId
),
vote_agg AS (
    SELECT
        v.PostId,
        SUM(CASE 
                WHEN v.VoteTypeId = 2 THEN 1      -- UpMod
                WHEN v.VoteTypeId = 3 THEN -1     -- DownMod
                ELSE 0
            END) AS net_votes
    FROM Votes v
    GROUP BY v.PostId
),
user_vote_totals AS (
    SELECT
        p.OwnerUserId AS user_id,
        SUM(COALESCE(va.net_votes,0)) AS total_net_votes
    FROM Posts p
    LEFT JOIN vote_agg va
        ON va.PostId = p.Id
    GROUP BY p.OwnerUserId
),
top_question AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS rn,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1                      -- Question
      AND p.Score IS NOT NULL
),
user_top_question AS (
    SELECT
        tq.OwnerUserId AS user_id,
        tq.Title AS top_question_title,
        tq.Score AS top_question_score
    FROM top_question tq
    WHERE tq.rn = 1
),
combined AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ups.post_count,
        ups.avg_score,
        ups.sql_tag_posts,
        rb.recent_badge_list,
        uv.total_net_votes,
        utq.top_question_title,
        utq.top_question_score
    FROM Users u
    LEFT JOIN user_post_stats ups
        ON ups.user_id = u.Id
    LEFT JOIN recent_badges rb
        ON rb.UserId = u.Id
    LEFT JOIN user_vote_totals uv
        ON uv.user_id = u.Id
    LEFT JOIN user_top_question utq
        ON utq.user_id = u.Id
    WHERE (u.Reputation > 10000 OR ups.post_count > 10)
      AND (ups.avg_score IS NULL OR ups.avg_score > 0)
      AND COALESCE(rb.recent_badge_list, '') <> ''
),
ranked AS (
    SELECT
        c.*,
        RANK() OVER (ORDER BY c.Reputation DESC, c.post_count DESC) AS reputation_rank
    FROM combined c
)
SELECT
    r.Id,
    r.DisplayName,
    r.Reputation,
    r.reputation_rank,
    r.post_count,
    ROUND(r.avg_score::numeric,2)          AS avg_score,
    r.sql_tag_posts,
    r.recent_badge_list,
    r.total_net_votes,
    r.top_question_title,
    r.top_question_score
FROM ranked r
WHERE r.reputation_rank <= 100
ORDER BY r.reputation_rank, r.post_count DESC;
