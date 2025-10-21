-- {"query": "17063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1895}

WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers_given,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as avg_question_score,
        SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) as high_score_posts,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) as tag,
        COUNT(*) as tag_count,
        SUM(p.Score) as tag_score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
        AND p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId, tag
),
recursive_comment_chains AS (
    WITH RECURSIVE comment_tree AS (
        SELECT 
            c.Id,
            c.PostId,
            c.UserId,
            c.CreationDate,
            1 as depth,
            c.Id::text as path
        FROM Comments c
        WHERE c.UserId IN (SELECT Id FROM Users WHERE Reputation > 10000)
        
        UNION ALL
        
        SELECT 
            c2.Id,
            c2.PostId,
            c2.UserId,
            c2.CreationDate,
            ct.depth + 1,
            ct.path || ',' || c2.Id::text
        FROM Comments c2
        JOIN comment_tree ct ON c2.PostId = ct.PostId 
            AND c2.CreationDate > ct.CreationDate
            AND c2.CreationDate < ct.CreationDate + INTERVAL '1 hour'
        WHERE ct.depth < 5
    )
    SELECT PostId, MAX(depth) as max_chain_depth
    FROM comment_tree
    GROUP BY PostId
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.total_posts,
    COALESCE(uam.avg_question_score, 0) as avg_question_score,
    te.tag as top_tag,
    te.tag_score as top_tag_total_score,
    DENSE_RANK() OVER (ORDER BY uam.Reputation DESC) as reputation_rank,
    LAG(uam.Reputation, 1) OVER (ORDER BY uam.Reputation DESC) - uam.Reputation as rep_diff_from_higher,
    CASE 
        WHEN uam.questions_asked > 0 THEN 
            ROUND((uam.answers_given::numeric / NULLIF(uam.questions_asked, 0)) * 100, 2)
        ELSE NULL 
    END as answer_to_question_ratio,
    STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Class, b.Name) FILTER (WHERE b.Class = 1) as gold_badges,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = uam.Id
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '6 months'
    ) as recent_edits,
    EXISTS (
        SELECT 1
        FROM Posts p_accepted
        WHERE p_accepted.AcceptedAnswerId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = uam.Id
        )
    ) as has_accepted_answer,
    COALESCE(
        (
            SELECT AVG(v.BountyAmount)
            FROM Votes v
            JOIN Posts p_bounty ON v.PostId = p_bounty.Id
            WHERE v.VoteTypeId = 8
                AND p_bounty.OwnerUserId = uam.Id
                AND v.BountyAmount IS NOT NULL
        ), 0
    ) as avg_bounty_offered,
    CASE 
        WHEN uam.DisplayName IS NULL THEN 'Anonymous'
        WHEN UPPER(SUBSTRING(uam.DisplayName, 1, 1)) = SUBSTRING(uam.DisplayName, 1, 1) 
            THEN 'Proper Case'
        ELSE 'Lowercase Start'
    END as name_format,
    COALESCE(rcc.max_chain_depth, 0) as longest_comment_chain,
    GREATEST(
        EXTRACT(EPOCH FROM (
            SELECT MAX(p_last.LastActivityDate) 
            FROM Posts p_last 
            WHERE p_last.OwnerUserId = uam.Id
        ) - (
            SELECT MIN(p_first.CreationDate) 
            FROM Posts p_first 
            WHERE p_first.OwnerUserId = uam.Id
        )) / 86400,
        0
    )::int as active_days_span
FROM user_activity_metrics uam
LEFT JOIN tag_expertise te ON uam.Id = te.OwnerUserId AND te.tag_rank = 1
LEFT JOIN Badges b ON uam.Id = b.UserId
LEFT JOIN LATERAL (
    SELECT PostId, max_chain_depth
    FROM recursive_comment_chains
    WHERE PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = uam.Id)
    ORDER BY max_chain_depth DESC
    LIMIT 1
) rcc ON true
WHERE uam.total_posts > 5
    AND (uam.Reputation > 1000 OR uam.high_score_posts > 0)
    AND NOT EXISTS (
        SELECT 1 
        FROM PostHistory ph_del
        WHERE ph_del.UserId = uam.Id 
            AND ph_del.PostHistoryTypeId = 12
            AND ph_del.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 months'
    )
GROUP BY 
    uam.Id,
    uam.DisplayName,
    uam.Reputation,
    uam.total_posts,
    uam.questions_asked,
    uam.answers_given,
    uam.avg_question_score,
    uam.high_score_posts,
    uam.median_score,
    te.tag,
    te.tag_score,
    rcc.max_chain_depth
HAVING COUNT(DISTINCT b.Id) FILTER (WHERE b.TagBased = '0') >= 2
    OR uam.median_score > 5
ORDER BY 
    uam.Reputation DESC,
    COALESCE(te.tag_score, 0) DESC,
    uam.total_posts DESC
LIMIT 100;
