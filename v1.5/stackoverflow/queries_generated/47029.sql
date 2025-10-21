-- {"query": "47029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1839}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as question_count,
        1 as level
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    JOIN Posts pt ON pt.Id = p.Id AND pt.PostTypeId = 1
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        string_agg(DISTINCT substring(p.Tags, 2, length(p.Tags)-2), ', ') as expertise_tags,
        COUNT(DISTINCT p.Id) as answer_count,
        AVG(p.Score) as avg_answer_score,
        SUM(p.Score) as total_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        STDDEV(p.Score) as score_variance
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2 
        AND p.Score > 0
        AND u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
question_complexity AS (
    SELECT 
        q.Id,
        q.Title,
        q.CreationDate,
        LENGTH(q.Body) as body_length,
        q.ViewCount,
        q.Score as question_score,
        q.AnswerCount,
        q.CommentCount,
        COALESCE(q.FavoriteCount, 0) as favorite_count,
        EXTRACT(EPOCH FROM (COALESCE(a.CreationDate, NOW()) - q.CreationDate))/3600 as hours_to_first_answer,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN ph.Id END) as close_reopen_cycles,
        MAX(CASE WHEN b.Name IN ('Popular Question', 'Notable Question', 'Famous Question') THEN 1 ELSE 0 END) as is_popular
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY q.Id, q.Title, q.CreationDate, q.Body, q.ViewCount, q.Score, q.AnswerCount, q.CommentCount, q.FavoriteCount, a.CreationDate
),
voting_patterns AS (
    SELECT 
        DATE_TRUNC('month', v.CreationDate) as vote_month,
        vt.Name as vote_type,
        COUNT(*) as vote_count,
        COUNT(DISTINCT v.UserId) as unique_voters,
        COUNT(DISTINCT v.PostId) as unique_posts,
        AVG(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount END) as avg_bounty
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY DATE_TRUNC('month', v.CreationDate), vt.Name
),
badge_distribution AS (
    SELECT 
        b.Name as badge_name,
        CASE b.Class 
            WHEN 1 THEN 'Gold'
            WHEN 2 THEN 'Silver'
            WHEN 3 THEN 'Bronze'
        END as badge_class,
        COUNT(DISTINCT b.UserId) as recipients,
        MIN(b.Date) as first_awarded,
        MAX(b.Date) as last_awarded,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY u.Reputation) as q1_reputation,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) as median_reputation,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY u.Reputation) as q3_reputation
    FROM Badges b
    JOIN Users u ON u.Id = b.UserId
    GROUP BY b.Name, b.Class
    HAVING COUNT(DISTINCT b.UserId) > 100
)
SELECT 
    ue.DisplayName as expert_name,
    ue.Reputation as expert_reputation,
    ue.answer_count,
    ROUND(ue.avg_answer_score::numeric, 2) as avg_answer_score,
    ue.total_score,
    qc.Title as complex_question,
    qc.question_score,
    qc.ViewCount as views,
    qc.AnswerCount as answers,
    ROUND(qc.hours_to_first_answer::numeric, 1) as hours_to_answer,
    qc.edit_count,
    qc.close_reopen_cycles,
    th.TagName as popular_tag,
    th.question_count as tag_questions,
    vp.vote_type,
    vp.vote_count as monthly_votes,
    vp.unique_voters,
    COALESCE(vp.avg_bounty, 0) as avg_bounty_amount,
    bd.badge_name,
    bd.badge_class,
    bd.recipients as badge_recipients,
    ROUND(bd.median_reputation::numeric, 0) as badge_median_rep,
    DENSE_RANK() OVER (ORDER BY ue.total_score DESC) as expert_rank,
    DENSE_RANK() OVER (ORDER BY qc.ViewCount DESC) as question_popularity_rank,
    LAG(vp.vote_count, 1) OVER (PARTITION BY vp.vote_type ORDER BY vp.vote_month) as prev_month_votes,
    ROUND((vp.vote_count - LAG(vp.vote_count, 1) OVER (PARTITION BY vp.vote_type ORDER BY vp.vote_month))::numeric / 
          NULLIF(LAG(vp.vote_count, 1) OVER (PARTITION BY vp.vote_type ORDER BY vp.vote_month), 0) * 100, 2) as vote_growth_percent
FROM user_expertise ue
CROSS JOIN question_complexity qc
CROSS JOIN tag_hierarchy th
CROSS JOIN voting_patterns vp
CROSS JOIN badge_distribution bd
WHERE qc.is_popular = 1
    AND th.question_count > 5000
    AND vp.vote_count > 1000
    AND bd.badge_class IN ('Gold', 'Silver')
ORDER BY 
    ue.total_score DESC,
    qc.ViewCount DESC,
    vp.vote_count DESC
LIMIT 100;
