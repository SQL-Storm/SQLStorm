WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) AS question_count,
        1 AS level
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE pt.PostTypeId = 1
      AND t.Count > 1000
    GROUP BY t.Id, t.TagName

    UNION ALL

    SELECT 
        t2.Id,
        t2.TagName,
        COALESCE(agg.question_count, 0) AS question_count,
        th.level + 1
    FROM tag_hierarchy th
    CROSS JOIN Tags t2
    INNER JOIN (
        SELECT p.Id AS post_id
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.Id
    ) p ON TRUE
    INNER JOIN Posts p1 ON p1.Id = p.post_id AND p1.Tags LIKE '%' || '<' || th.TagName || '>' || '%'
    INNER JOIN Posts p2 ON p2.Id = p.post_id AND p2.Tags LIKE '%' || '<' || t2.TagName || '>' || '%'
    LEFT JOIN (
        SELECT p_shared.post_id, COUNT(DISTINCT p_shared.post_id) AS question_count
        FROM (
            SELECT p_inner.Id AS post_id
            FROM Posts p_inner
        ) p_shared
        GROUP BY p_shared.post_id
    ) agg ON TRUE
    WHERE th.level < 3
      AND t2.Id != th.Id
    GROUP BY t2.Id, t2.TagName, th.level, agg.question_count
),
user_expertise AS (
    SELECT 
        u.Id AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_given,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_answer_score,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score >= 10 THEN p.Id END) AS high_score_answers,
        COUNT(DISTINCT b.Id) AS badge_count,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_post_score
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 5000
      AND u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '365 days')
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_quality_metrics AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        COUNT(DISTINCT ph.UserId) AS unique_editors,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS edit_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS was_closed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS was_reopened,
        COUNT(DISTINCT c.Id) AS comment_count,
        AVG(c.Score) AS avg_comment_score,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END) AS linked_posts,
        COUNT(DISTINCT CASE WHEN pl2.LinkTypeId = 3 THEN pl2.Id END) AS duplicate_links,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, CAST('2024-10-01 12:34:56' AS timestamp)) - p.CreationDate))/3600 AS hours_until_closed,
        p.ClosedDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.Score > 0
      AND p.CreationDate BETWEEN (CAST('2024-10-01' AS date) - INTERVAL '2 years') AND (CAST('2024-10-01' AS date) - INTERVAL '6 months')
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.ClosedDate
),
answer_response_times AS (
    SELECT 
        q.Id AS question_id,
        a.Id AS answer_id,
        a.Score AS answer_score,
        a.OwnerUserId AS answerer_id,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60 AS minutes_to_first_answer,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.CreationDate) AS answer_order,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS is_accepted
    FROM Posts q
    INNER JOIN Posts a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1 
      AND a.PostTypeId = 2
      AND q.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '2 years')
)
SELECT 
    th.TagName,
    th.question_count,
    ue.DisplayName AS top_expert,
    ue.Reputation,
    ue.avg_answer_score,
    ue.gold_badges,
    pqm.Title AS quality_post,
    pqm.Score AS post_score,
    pqm.ViewCount,
    pqm.edit_count,
    pqm.upvotes,
    pqm.downvotes,
    ROUND(COALESCE(pqm.upvotes,0) * 1.0 / NULLIF(COALESCE(pqm.upvotes,0) + COALESCE(pqm.downvotes,0), 0) * 100, 2) AS upvote_ratio,
    art.minutes_to_first_answer,
    art.answer_score AS first_answer_score,
    art.is_accepted,
    COUNT(*) OVER (PARTITION BY th.TagName) AS posts_per_tag,
    DENSE_RANK() OVER (PARTITION BY th.TagName ORDER BY pqm.Score DESC) AS score_rank_in_tag,
    LAG(pqm.Score, 1) OVER (PARTITION BY th.TagName ORDER BY pqm.CreationDate) AS prev_post_score,
    LEAD(pqm.Score, 1) OVER (PARTITION BY th.TagName ORDER BY pqm.CreationDate) AS next_post_score,
    NTILE(10) OVER (ORDER BY pqm.ViewCount) AS view_decile,
    CUME_DIST() OVER (ORDER BY ue.Reputation) AS reputation_percentile
FROM tag_hierarchy th
CROSS JOIN LATERAL (
    SELECT ue2.*
    FROM user_expertise ue2
    ORDER BY ue2.high_score_answers DESC, ue2.avg_answer_score DESC
    LIMIT 1
) ue
CROSS JOIN LATERAL (
    SELECT pqm2.*
    FROM post_quality_metrics pqm2
    WHERE pqm2.edit_count > 2
    ORDER BY pqm2.Score DESC, pqm2.ViewCount DESC
    LIMIT 1
) pqm
LEFT JOIN answer_response_times art ON art.question_id = pqm.Id AND art.answer_order = 1
WHERE th.level = 1
  AND th.question_count > 100
ORDER BY 
    th.question_count DESC,
    ue.Reputation DESC,
    pqm.Score DESC
LIMIT 100;