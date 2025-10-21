-- {"query": "47075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1838}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as question_count,
        1 as level
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
    AND t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        SUM(p.Score) as total_score_in_tag,
        AVG(p.Score) as avg_score_in_tag,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as rank_in_tag
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
    AND p.Score > 0
    AND u.Reputation > 5000
    AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
question_quality AS (
    SELECT 
        p.Id as question_id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END as has_accepted,
        COALESCE(p.ViewCount / NULLIF(p.AnswerCount, 0), 0) as views_per_answer,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.Count DESC) as tag_list,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as edit_count,
        COUNT(DISTINCT c.Id) as comment_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) as was_hot_network
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    AND p.Score >= 5
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, 
             p.FavoriteCount, p.CreationDate, p.AcceptedAnswerId
),
badge_analysis AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) as gold_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) as silver_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) as bronze_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.TagBased = true) as tag_badges,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Class, b.Date DESC) FILTER (WHERE b.Class = 1) as gold_badge_names
    FROM Badges b
    WHERE b.Date >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY b.UserId
),
voting_patterns AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) as upvotes_given,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) as downvotes_given,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 8) as bounties_started,
        SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) as total_bounty_offered,
        DATE_TRUNC('month', v.CreationDate) as vote_month
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '6 months'
    AND v.UserId IS NOT NULL
    GROUP BY v.UserId, DATE_TRUNC('month', v.CreationDate)
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.TagName as expertise_tag,
    ue.answers_in_tag,
    ue.avg_score_in_tag,
    ue.rank_in_tag,
    COUNT(DISTINCT qq.question_id) as quality_questions_asked,
    AVG(qq.Score) as avg_question_score,
    AVG(qq.views_per_answer) as avg_views_per_answer,
    SUM(qq.was_hot_network) as hot_network_questions,
    COALESCE(ba.gold_badges, 0) as gold_badges,
    COALESCE(ba.silver_badges, 0) as silver_badges,
    COALESCE(ba.tag_badges, 0) as tag_specific_badges,
    COALESCE(ba.gold_badge_names, 'None') as gold_achievements,
    COALESCE(AVG(vp.upvotes_given), 0) as avg_monthly_upvotes,
    COALESCE(SUM(vp.bounties_started), 0) as bounties_offered,
    COALESCE(SUM(vp.total_bounty_offered), 0) as total_bounty_amount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qq.Score) as median_question_score,
    STDDEV(qq.Score) as question_score_stddev
FROM user_expertise ue
LEFT JOIN question_quality qq ON qq.OwnerUserId = ue.user_id
LEFT JOIN badge_analysis ba ON ba.UserId = ue.user_id
LEFT JOIN voting_patterns vp ON vp.UserId = ue.user_id
WHERE ue.rank_in_tag <= 100
GROUP BY 
    ue.DisplayName,
    ue.Reputation,
    ue.TagName,
    ue.answers_in_tag,
    ue.avg_score_in_tag,
    ue.rank_in_tag,
    ba.gold_badges,
    ba.silver_badges,
    ba.tag_badges,
    ba.gold_badge_names
HAVING COUNT(DISTINCT qq.question_id) > 0
ORDER BY 
    ue.avg_score_in_tag DESC,
    ue.Reputation DESC,
    gold_badges DESC
LIMIT 500;
