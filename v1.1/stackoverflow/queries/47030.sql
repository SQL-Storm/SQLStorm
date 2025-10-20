WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) AS question_count,
        1 AS level
    FROM Tags t
    JOIN Posts pt ON pt.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE pt.PostTypeId = 1
      AND t.Count > 1000
    GROUP BY t.Id, t.TagName

    UNION ALL

    SELECT 
        th_inner.parent_tag_id AS Id,
        th_inner.parent_tagname AS TagName,
        th_inner.child_question_count AS question_count,
        th_inner.level + 1 AS level
    FROM (
        -- compute related-tag counts per parent tag without aggregates in recursive term;
        -- this subselect is non-recursive and will be joined to the recursive member
        SELECT
            th0.Id AS parent_tag_id,
            th0.TagName AS parent_tagname,
            t2_inner.Id AS child_tag_id,
            t2_inner.TagName AS child_tagname,
            COUNT(DISTINCT p2_inner.Id) AS child_question_count,
            th0.level
        FROM (
            -- reference base-level tags from the non-recursive part of tag_hierarchy
            SELECT 
                t.Id,
                t.TagName,
                COUNT(DISTINCT pt.Id) AS question_count,
                1 AS level
            FROM Tags t
            JOIN Posts pt ON pt.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
            WHERE pt.PostTypeId = 1
              AND t.Count > 1000
            GROUP BY t.Id, t.TagName
        ) th0
        JOIN Posts p1_inner ON p1_inner.Tags LIKE '%' || '<' || th0.TagName || '>' || '%'
        JOIN Posts p2_inner ON p2_inner.Tags LIKE '%' || '<' || th0.TagName || '>' || '%'
            AND p2_inner.Id != p1_inner.Id
            AND p2_inner.Tags != p1_inner.Tags
        JOIN Tags t2_inner ON p2_inner.Tags LIKE '%' || '<' || t2_inner.TagName || '>' || '%'
            AND t2_inner.Id != th0.Id
        WHERE th0.level < 3
          AND p1_inner.PostTypeId = 1
          AND p2_inner.PostTypeId = 1
        GROUP BY th0.Id, th0.TagName, t2_inner.Id, t2_inner.TagName, th0.level
    ) th_inner
    JOIN Tags t2 ON t2.Id = th_inner.child_tag_id
    WHERE th_inner.level < 3
),
user_expertise AS (
    SELECT 
        u.Id AS user_id,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) AS answers,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) AS accepted_answers,
        COUNT(DISTINCT b.Id) AS tag_badges,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) AS tag_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS global_answer_rank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    JOIN Posts q ON p.ParentId = q.Id
    JOIN Tags t ON q.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN Badges b ON b.UserId = u.Id 
        AND b.TagBased = TRUE 
        AND LOWER(b.Name) = LOWER(t.TagName)
    WHERE u.Reputation > 5000
      AND p.Score > 0
    GROUP BY u.Id, u.DisplayName, t.TagName
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) AS month,
        pt.Name AS post_type,
        COUNT(DISTINCT p.Id) AS posts,
        COUNT(DISTINCT p.OwnerUserId) AS unique_authors,
        AVG(p.Score) AS avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.Score) AS p90_score,
        COUNT(DISTINCT c.Id) AS total_comments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS edits,
        AVG(EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - p.CreationDate))/3600) AS avg_hours_to_close
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '2 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate), pt.Name
)
SELECT 
    ue.DisplayName,
    ue.TagName,
    ue.answers,
    ue.total_score,
    ue.avg_score,
    ue.accepted_answers,
    ROUND(100.0 * ue.accepted_answers / NULLIF(ue.answers, 0), 2) AS acceptance_rate,
    ue.tag_badges,
    ue.tag_rank,
    ue.global_answer_rank,
    th.question_count AS tag_question_count,
    th.level AS tag_hierarchy_level,
    tp.month,
    tp.posts AS monthly_posts,
    tp.avg_score AS monthly_avg_score,
    tp.median_score AS monthly_median_score,
    tp.total_comments AS monthly_comments,
    tp.upvotes AS monthly_upvotes,
    tp.downvotes AS monthly_downvotes,
    tp.edits AS monthly_edits,
    ROUND(tp.avg_hours_to_close, 2) AS avg_hours_to_close,
    COUNT(*) OVER (PARTITION BY ue.TagName ORDER BY ue.total_score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_experts,
    LAG(ue.total_score, 1) OVER (PARTITION BY ue.TagName ORDER BY ue.total_score DESC) - ue.total_score AS score_gap_to_previous,
    FIRST_VALUE(ue.total_score) OVER (PARTITION BY ue.TagName ORDER BY ue.total_score DESC) - ue.total_score AS score_gap_to_top
FROM user_expertise ue
JOIN tag_hierarchy th ON th.TagName = ue.TagName
CROSS JOIN temporal_patterns tp
WHERE ue.tag_rank <= 100
  AND tp.post_type = 'Question'
ORDER BY ue.TagName, ue.tag_rank, tp.month DESC;