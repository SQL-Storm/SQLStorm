-- {"query": "16035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 84060, "output_tokens": 78438} 

WITH RECURSIVE user_engagement_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS net_votes,
        EXTRACT(YEAR FROM u.CreationDate) AS join_year,
        CASE 
            WHEN u.Location IS NULL THEN 'Unknown'
            WHEN LENGTH(TRIM(u.Location)) = 0 THEN 'Unknown'
            ELSE SUBSTRING(u.Location, 1, POSITION(',' IN u.Location || ',') - 1)
        END AS primary_location
    FROM Users u
    WHERE u.Reputation > 1000
        AND u.CreationDate >= '2020-01-01'
),
post_quality_scores AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS comment_count,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1.5
            WHEN p.ClosedDate IS NOT NULL THEN 0.5
            ELSE 1.0
        END AS quality_multiplier,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) AS post_rank,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.OwnerUserId IS NOT NULL
),
badge_hierarchy AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 AND b.TagBased = 1 THEN b.Name ELSE NULL END, '; ') AS gold_tag_badges,
        MAX(b.Date) AS latest_badge_date,
        COUNT(DISTINCT EXTRACT(MONTH FROM b.Date)) AS active_months
    FROM Badges b
    GROUP BY b.UserId
),
answer_acceptance_rates AS (
    SELECT 
        q.OwnerUserId AS questioner_id,
        COUNT(*) AS total_questions,
        COUNT(q.AcceptedAnswerId) AS accepted_questions,
        ROUND(100.0 * COUNT(q.AcceptedAnswerId) / NULLIF(COUNT(*), 0), 2) AS acceptance_rate,
        AVG(a.Score) FILTER (WHERE a.Id = q.AcceptedAnswerId) AS avg_accepted_answer_score
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1
        AND q.OwnerUserId IS NOT NULL
    GROUP BY q.OwnerUserId
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        tag_elem AS tag_name,
        COUNT(*) AS tag_usage_count,
        AVG(p.Score) AS avg_score_in_tag,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.Score) AS score_percentile_75
    FROM Posts p
    CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(COALESCE(p.Tags, '')) - 2), '><') AS tag_elem
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tag_elem
    HAVING COUNT(*) >= 5
),
top_tags_per_user AS (
    SELECT 
        te.OwnerUserId,
        STRING_AGG(te.tag_name, ', ' ORDER BY te.tag_usage_count DESC) FILTER (WHERE tag_rank <= 3) AS top_3_tags,
        MAX(te.avg_score_in_tag) FILTER (WHERE tag_rank = 1) AS best_tag_avg_score
    FROM (
        SELECT 
            te.*,
            ROW_NUMBER() OVER (PARTITION BY te.OwnerUserId ORDER BY te.tag_usage_count DESC, te.avg_score_in_tag DESC) AS tag_rank
        FROM tag_expertise te
    ) te
    WHERE tag_rank <= 5
    GROUP BY te.OwnerUserId
),
voting_patterns AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes_given,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes_given,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites_given,
        COUNT(DISTINCT v.PostId) AS unique_posts_voted,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS bounties_started,
        COALESCE(SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8), 0) AS total_bounty_amount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
comment_activity AS (
    SELECT 
        c.UserId,
        COUNT(*) AS total_comments,
        AVG(c.Score) AS avg_comment_score,
        COUNT(DISTINCT c.PostId) AS unique_posts_commented,
        MAX(LENGTH(c.Text)) AS longest_comment_length
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    uem.Id AS user_id,
    uem.DisplayName,
    uem.Reputation,
    uem.primary_location,
    uem.join_year,
    COALESCE(bh.gold_badges, 0) AS gold_count,
    COALESCE(bh.silver_badges, 0) AS silver_count,
    COALESCE(bh.bronze_badges, 0) AS bronze_count,
    bh.gold_tag_badges,
    COALESCE(aar.acceptance_rate, 0) AS question_acceptance_rate,
    COALESCE(aar.total_questions, 0) AS total_questions_asked,
    ttu.top_3_tags,
    ROUND(COALESCE(ttu.best_tag_avg_score, 0), 2) AS best_tag_performance,
    COALESCE(vp.upvotes_given, 0) AS upvotes_cast,
    COALESCE(vp.downvotes_given, 0) AS downvotes_cast,
    COALESCE(vp.total_bounty_amount, 0) AS reputation_spent_on_bounties,
    COALESCE(ca.total_comments, 0) AS comments_posted,
    COALESCE(ca.avg_comment_score, 0) AS avg_comment_score,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = uem.Id
            AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS posts_edited,
    (
        SELECT AVG(pqs.Score * pqs.quality_multiplier)
        FROM post_quality_scores pqs
        WHERE pqs.OwnerUserId = uem.Id
            AND pqs.post_rank <= 10
    ) AS top_10_weighted_avg_score,
    (
        SELECT COUNT(*)
        FROM Posts answers
        INNER JOIN Posts questions ON answers.ParentId = questions.Id
        WHERE answers.OwnerUserId = uem.Id
            AND answers.PostTypeId = 2
            AND questions.AcceptedAnswerId = answers.Id
    ) AS accepted_answers_count,
    CASE 
        WHEN uem.Reputation >= 25000 THEN 'Elite'
        WHEN uem.Reputation >= 10000 THEN 'Expert'
        WHEN uem.Reputation >= 5000 THEN 'Advanced'
        WHEN uem.Reputation >= 2000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS reputation_tier,
    ROUND(
        (COALESCE(bh.gold_badges, 0) * 3 + COALESCE(bh.silver_badges, 0) * 2 + COALESCE(bh.bronze_badges, 0)) / 
        NULLIF(GREATEST(EXTRACT(EPOCH FROM (CURRENT_DATE - uem.CreationDate)) / 86400, 1), 0),
        4
    ) AS badges_per_day,
    EXISTS (
        SELECT 1 
        FROM Votes v2
        WHERE v2.UserId = uem.Id 
            AND v2.VoteTypeId = 14
    ) AS nominated_for_moderator
FROM user_engagement_metrics uem
LEFT JOIN badge_hierarchy bh ON uem.Id = bh.UserId
LEFT JOIN answer_acceptance_rates aar ON uem.Id = aar.questioner_id
LEFT JOIN top_tags_per_user ttu ON uem.Id = ttu.OwnerUserId
LEFT JOIN voting_patterns vp ON uem.Id = vp.UserId
LEFT JOIN comment_activity ca ON uem.Id = ca.UserId
WHERE (
    COALESCE(bh.gold_badges, 0) + COALESCE(bh.silver_badges, 0) + COALESCE(bh.bronze_badges, 0) > 10
    OR uem.Reputation > 5000
    OR (
        SELECT COUNT(*) 
        FROM post_quality_scores pqs2 
        WHERE pqs2.OwnerUserId = uem.Id 
            AND pqs2.Score > 10
    ) > 5
)
ORDER BY 
    COALESCE(bh.gold_badges, 0) * 100 + COALESCE(bh.silver_badges, 0) * 10 + COALESCE(bh.bronze_badges, 0) DESC,
    uem.Reputation DESC,
    uem.net_votes DESC
LIMIT 1000;
