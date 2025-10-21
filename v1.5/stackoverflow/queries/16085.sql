WITH RECURSIVE user_engagement_scores AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS rep_rank,
        PERCENT_RANK() OVER (ORDER BY u.Reputation) AS rep_percentile,
        EXTRACT(YEAR FROM u.CreationDate) AS join_year
    FROM Users u
    WHERE u.Reputation > 100
),
post_complexity_metrics AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        LENGTH(p.Body) AS body_length,
        COALESCE(p.CommentCount, 0) AS comments,
        COALESCE(p.AnswerCount, 0) AS answers,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS has_accepted_answer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 
                (CAST(EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) AS numeric)) / 3600.0
            ELSE NULL
        END AS hours_until_closed,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS tag_array,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS rolling_avg_score
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '3 years'
),
badge_momentum AS (
    SELECT 
        b.UserId,
        COUNT(*) AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS weighted_badge_score,
        COUNT(*) FILTER (WHERE b.Date >= CAST('2024-10-01' AS DATE) - INTERVAL '6 months') AS recent_badges,
        STRING_AGG(DISTINCT b.Name, '; ' ORDER BY b.Name) AS badge_names,
        MAX(b.Date) AS last_badge_date
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(*) >= 3
),
answer_effectiveness AS (
    SELECT 
        a.OwnerUserId,
        COUNT(*) AS total_answers,
        COUNT(*) FILTER (WHERE q.AcceptedAnswerId = a.Id) AS accepted_answers,
        ROUND(100.0 * COUNT(*) FILTER (WHERE q.AcceptedAnswerId = a.Id) / NULLIF(COUNT(*), 0), 2) AS acceptance_rate,
        AVG(a.Score) AS avg_answer_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS median_answer_score,
        MAX(a.Score) AS best_answer_score
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
        AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
)
SELECT 
    ues.DisplayName,
    ues.Reputation,
    ues.rep_rank,
    ROUND(CAST(UES.rep_percentile AS numeric), 4) AS reputation_percentile,
    ues.join_year,
    COALESCE(bm.total_badges, 0) AS badges,
    COALESCE(bm.weighted_badge_score, 0) AS badge_score,
    COALESCE(bm.recent_badges, 0) AS recent_badges,
    SUBSTRING(COALESCE(bm.badge_names, 'None'), 1, 100) AS top_badges,
    COUNT(DISTINCT pcm.post_id) AS total_posts,
    ROUND(AVG(pcm.body_length), 0) AS avg_post_length,
    ROUND(AVG(pcm.Score), 2) AS avg_post_score,
    COALESCE(SUM(pcm.ViewCount), 0) AS total_views,
    ae.total_answers,
    COALESCE(ae.acceptance_rate, 0) AS answer_acceptance_rate,
    COALESCE(ae.median_answer_score, 0) AS median_answer_score,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 8) AS bounties_started,
    COALESCE(SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8), 0) AS total_bounty_offered,
    ARRAY_AGG(DISTINCT tag_elem ORDER BY tag_elem) FILTER (WHERE tag_elem IS NOT NULL) AS top_tags,
    ROUND(
        (ues.Reputation * 0.4 + 
         COALESCE(bm.weighted_badge_score, 0) * 50 + 
         COALESCE(ae.acceptance_rate, 0) * 10 +
         COALESCE(ae.avg_answer_score, 0) * 20)::numeric, 
        2
    ) AS composite_influence_score,
    CASE 
        WHEN ues.Reputation > 10000 AND COALESCE(ae.acceptance_rate, 0) > 30 THEN 'Elite Contributor'
        WHEN ues.Reputation > 5000 OR COALESCE(bm.total_badges, 0) > 10 THEN 'Advanced Contributor'
        WHEN ues.Reputation > 1000 THEN 'Regular Contributor'
        ELSE 'Emerging Contributor'
    END AS contributor_tier
FROM user_engagement_scores ues
LEFT OUTER JOIN post_complexity_metrics pcm ON ues.Id = pcm.OwnerUserId
LEFT OUTER JOIN badge_momentum bm ON ues.Id = bm.UserId
LEFT OUTER JOIN answer_effectiveness ae ON ues.Id = ae.OwnerUserId
LEFT OUTER JOIN Votes v ON ues.Id = v.UserId
LEFT JOIN LATERAL UNNEST(pcm.tag_array) AS tag_elem ON TRUE
WHERE ues.rep_rank <= 1000
    AND (pcm.post_id IS NULL OR pcm.Score >= -5)
    AND NOT EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = ues.Id 
            AND p2.ClosedDate IS NOT NULL 
            AND p2.Score < -3
        HAVING COUNT(*) > 5
    )
GROUP BY 
    ues.Id, ues.DisplayName, ues.Reputation, ues.rep_rank, 
    ues.rep_percentile, ues.join_year, ues.NetVotes,
    bm.total_badges, bm.weighted_badge_score, bm.recent_badges, bm.badge_names,
    ae.total_answers, ae.acceptance_rate, ae.avg_answer_score, ae.median_answer_score
HAVING COUNT(DISTINCT pcm.post_id) > 0 OR COALESCE(ae.total_answers, 0) > 0
ORDER BY composite_influence_score DESC, ues.Reputation DESC
LIMIT 100;