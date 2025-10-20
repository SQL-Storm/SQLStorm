-- {"query": "55007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1534} 

/*  Complex benchmarking query – combines CTEs, window functions, JSON handling, 
    array aggregation and multiple joins across the StackOverflow schema  */
WITH RECURSIVE tag_hierarchy AS (
    /*  Build a simple tag co‑occurrence graph for the last 30 days  */
    SELECT
        t1.TagName   AS tag_a,
        t2.TagName   AS tag_b,
        COUNT(*)     AS co_occurs
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t1 ON true
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t2 ON t1.TagName < t2.TagName               -- avoid duplicate pairs and self‑join
    WHERE p.PostTypeId = 1                         -- questions only
      AND p.CreationDate >= now() - interval '30 days'
    GROUP BY t1.TagName, t2.TagName
    HAVING COUNT(*) > 5
),
user_activity AS (
    SELECT
        u.Id                         AS user_id,
        u.DisplayName                AS user_name,
        u.Reputation,
        COUNT(DISTINCT p.Id)         AS questions_posted,
        COUNT(DISTINCT a.Id)         AS answers_posted,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes_given,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes_given,
        COUNT(DISTINCT b.Id)         AS badges_earned,
        MAX(p.CreationDate)          AS last_question_date,
        MAX(a.CreationDate)          AS last_answer_date
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a   ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v   ON v.UserId = u.Id
    LEFT JOIN Badges b  ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_questions AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        COALESCE(ph.EditCount, 0)                AS edit_count,
        jsonb_agg(DISTINCT jsonb_build_object(
            'userId', v.UserId,
            'voteType', vt.Name,
            'date', v.CreationDate
        ) ORDER BY v.CreationDate DESC)        AS recent_votes,
        array_agg(DISTINCT t.TagName)            AS tags
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS EditCount
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (4,5,6)   -- edits
    ) ph ON true
    LEFT JOIN Votes v
        ON v.PostId = p.Id
       AND v.VoteTypeId IN (2,3)               -- up/down votes
    LEFT JOIN VoteTypes vt
        ON vt.Id = v.VoteTypeId
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t ON true
    WHERE p.PostTypeId = 1                       -- only questions
      AND p.CreationDate >= now() - interval '180 days'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.FavoriteCount, p.AnswerCount, ph.EditCount
),
question_closure AS (
    SELECT
        ph.PostId,
        MIN(ph.CreationDate)                                           AS closed_at,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)  AS close_reason_code,
        jsonb_agg(jsonb_build_object(
            'voterId', (ph.Text::jsonb)->>'UserId',
            'voteDate', (ph.Text::jsonb)->>'CreationDate'
        ))                                                             AS close_votes
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10                                   -- post closed
    GROUP BY ph.PostId
),
duplicate_links AS (
    SELECT
        pl.PostId      AS duplicate_of,
        pl.RelatedPostId AS original_question,
        pl.CreationDate
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3                                            -- duplicate link
)
SELECT
    ua.user_id,
    ua.user_name,
    ua.Reputation,
    ua.questions_posted,
    ua.answers_posted,
    ua.up_votes_given,
    ua.down_votes_given,
    ua.badges_earned,
    ua.last_question_date,
    ua.last_answer_date,
    tq.Id                         AS top_question_id,
    tq.Title,
    tq.Score,
    tq.ViewCount,
    tq.FavoriteCount,
    tq.AnswerCount,
    tq.edit_count,
    tq.recent_votes,
    tq.tags,
    qc.closed_at,
    qc.close_reason_code,
    qc.close_votes,
    dl.original_question,
    dl.CreationDate              AS duplicate_marked_at,
    th.tag_a,
    th.tag_b,
    th.co_occurs
FROM user_activity ua
LEFT JOIN top_questions tq          ON tq.Id = (
    SELECT Id FROM top_questions tq2
    WHERE tq2.Id IN (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = ua.user_id AND p.PostTypeId = 1
    )
    ORDER BY tq2.Score DESC, tq2.ViewCount DESC
    LIMIT 1
)
LEFT JOIN question_closure qc        ON qc.PostId = tq.Id
LEFT JOIN duplicate_links dl        ON dl.duplicate_of = tq.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM tag_hierarchy th
    WHERE th.tag_a = ANY (tq.tags) OR th.tag_b = ANY (tq.tags)
    ORDER BY th.co_occurs DESC
    LIMIT 5
) th ON true
ORDER BY ua.Reputation DESC, ua.user_id
LIMIT 100;
