WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) AS direct_questions,
        CAST(t.TagName AS VARCHAR(1000)) AS tag_path,
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
        th.direct_questions,
        CAST(th.tag_path || ' -> ' || t2.TagName AS VARCHAR(1000)) AS tag_path,
        th.level + 1 AS level
    FROM tag_hierarchy th
    CROSS JOIN Tags t2
    INNER JOIN Posts p1 ON p1.Tags LIKE '%' || '<' || th.TagName || '>' || '%'
    INNER JOIN Posts p2 ON p2.Tags LIKE '%' || '<' || t2.TagName || '>' || '%'
        AND p1.Id = p2.Id
    WHERE th.level < 3
        AND t2.Id != th.Id
        AND t2.Count > 500
),
user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS expert_tags,
        COUNT(DISTINCT p.Id) AS quality_answers,
        AVG(p.Score) AS avg_answer_score,
        SUM(p.Score) AS total_answer_score,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Name END) AS silver_badges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.TagBased = TRUE
    WHERE p.PostTypeId = 2
        AND p.Score > 5
        AND u.Reputation > 10000
        AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '2 years')
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
post_evolution AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate AS original_date,
        COUNT(DISTINCT ph.Id) AS edit_count,
        COUNT(DISTINCT ph.UserId) AS unique_editors,
        (MAX(ph.CreationDate) - MIN(p.CreationDate)) AS lifespan,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS content_edits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN ph.Id END) AS close_reopen_cycles,
        STRING_AGG(pht.Name, ' -> ' ORDER BY pht.Name) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13)) AS lifecycle
    FROM Posts p
    INNER JOIN PostHistory ph ON ph.PostId = p.Id
    INNER JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE p.PostTypeId = 1
        AND p.Score > 10
        AND p.ViewCount > 10000
    GROUP BY p.Id, p.Title, p.CreationDate
),
voting_patterns AS (
    SELECT 
        DATE_TRUNC('month', v.CreationDate) AS vote_month,
        vt.Name AS vote_type,
        COUNT(*) AS vote_count,
        COUNT(DISTINCT v.UserId) AS unique_voters,
        COUNT(DISTINCT v.PostId) AS unique_posts,
        AVG(p.Score) AS avg_post_score,
        STDDEV(p.Score) AS score_deviation,
        SUM(CASE WHEN p.OwnerUserId IN (SELECT ue.UserId FROM user_expertise ue) THEN 1 ELSE 0 END) AS expert_posts
    FROM Votes v
    INNER JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    INNER JOIN Posts p ON p.Id = v.PostId
    WHERE v.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
        AND v.VoteTypeId IN (2,3,5,8,9)
    GROUP BY DATE_TRUNC('month', v.CreationDate), vt.Name
)
SELECT 
    th.tag_path,
    th.level AS tag_depth,
    th.direct_questions,
    ue.DisplayName AS top_expert,
    ue.Reputation,
    ue.expert_tags,
    ue.quality_answers,
    ue.avg_answer_score,
    ue.gold_badges,
    ue.silver_badges,
    pe.Title AS evolved_question,
    pe.edit_count,
    pe.unique_editors,
    EXTRACT(day FROM pe.lifespan) AS days_active,
    pe.content_edits,
    pe.close_reopen_cycles,
    pe.lifecycle,
    vp.vote_month,
    vp.vote_type,
    vp.vote_count,
    vp.unique_voters,
    vp.avg_post_score,
    vp.score_deviation,
    vp.expert_posts,
    ROW_NUMBER() OVER (PARTITION BY th.tag_path ORDER BY ue.total_answer_score DESC) AS expert_rank,
    DENSE_RANK() OVER (ORDER BY vp.vote_count DESC) AS voting_intensity_rank,
    LAG(vp.vote_count, 1) OVER (PARTITION BY vp.vote_type ORDER BY vp.vote_month) AS prev_month_votes,
    LEAD(vp.vote_count, 1) OVER (PARTITION BY vp.vote_type ORDER BY vp.vote_month) AS next_month_votes
FROM tag_hierarchy th
CROSS JOIN user_expertise ue
CROSS JOIN post_evolution pe
CROSS JOIN voting_patterns vp
WHERE th.level <= 2
    AND ue.median_score > 10
    AND pe.edit_count > 5
ORDER BY 
    th.direct_questions DESC,
    ue.total_answer_score DESC,
    vp.vote_count DESC
LIMIT 1000;