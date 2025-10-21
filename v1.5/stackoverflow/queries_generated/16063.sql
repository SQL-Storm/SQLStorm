-- {"query": "16063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 149440, "output_tokens": 138217} 

WITH RECURSIVE user_influence AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS net_votes,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS rep_rank,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS yearly_rank
    FROM Users u
    WHERE u.Reputation > 1000
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '2 years'
),
post_metrics AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1.5
            WHEN p.ClosedDate IS NOT NULL THEN 0.5
            ELSE 1.0
        END AS quality_multiplier,
        LENGTH(COALESCE(p.Body, '')) / NULLIF(COALESCE(p.CommentCount, 0) + 1, 0) AS content_ratio,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 86400.0 AS activity_days,
        string_to_array(NULLIF(TRIM(BOTH '><' FROM COALESCE(p.Tags, '')), ''), '><') AS tag_array
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
),
tag_expertise AS (
    SELECT 
        pm.OwnerUserId,
        UNNEST(pm.tag_array) AS tag_name,
        COUNT(*) AS tag_post_count,
        AVG(pm.Score * pm.quality_multiplier) AS avg_weighted_score,
        SUM(CASE WHEN pm.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count
    FROM post_metrics pm
    WHERE pm.OwnerUserId IS NOT NULL
        AND pm.tag_array IS NOT NULL
    GROUP BY pm.OwnerUserId, UNNEST(pm.tag_array)
    HAVING COUNT(*) >= 5
),
engagement_scores AS (
    SELECT 
        v.UserId,
        COUNT(DISTINCT v.PostId) AS posts_voted_on,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_given,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_given,
        SUM(COALESCE(v.BountyAmount, 0)) AS total_bounty_offered,
        AVG(CASE WHEN v.VoteTypeId IN (2, 3) THEN 
            EXTRACT(EPOCH FROM (v.CreationDate - p.CreationDate)) / 3600.0 
            ELSE NULL END) AS avg_vote_delay_hours
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY v.UserId
),
badge_diversity AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT b.Name) AS unique_badges,
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS weighted_badge_score,
        MAX(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS has_tag_badges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ' ORDER BY b.Name) AS gold_badges
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '4 years'
    GROUP BY b.UserId
)
SELECT 
    ui.DisplayName,
    ui.Reputation,
    ui.rep_rank,
    COALESCE(es.posts_voted_on, 0) AS engagement_breadth,
    COALESCE(bd.weighted_badge_score, 0) AS achievement_score,
    (SELECT COUNT(*) FROM post_metrics pm2 
     WHERE pm2.OwnerUserId = ui.Id 
     AND pm2.Score >= (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) 
                       FROM post_metrics WHERE OwnerUserId IS NOT NULL)) AS top_quartile_posts,
    CASE 
        WHEN EXISTS (SELECT 1 FROM tag_expertise te 
                     WHERE te.OwnerUserId = ui.Id 
                     AND te.avg_weighted_score > 10) 
        THEN 'Expert'
        WHEN ui.Reputation > 10000 THEN 'Advanced'
        WHEN ui.Reputation > 5000 THEN 'Intermediate'
        ELSE 'Developing'
    END AS proficiency_tier,
    ROUND(CAST(COALESCE(es.upvotes_given, 0) AS NUMERIC) / 
          NULLIF(COALESCE(es.downvotes_given, 0), 0), 2) AS vote_positivity_ratio,
    (SELECT STRING_AGG(te.tag_name, ', ' ORDER BY te.avg_weighted_score DESC)
     FROM (SELECT tag_name, avg_weighted_score 
           FROM tag_expertise 
           WHERE OwnerUserId = ui.Id 
           ORDER BY avg_weighted_score DESC 
           LIMIT 5) te) AS top_expertise_tags,
    COALESCE(bd.gold_badges, 'None') AS prestigious_badges,
    AVG(pm.content_ratio) OVER (PARTITION BY ui.Id) AS avg_content_efficiency,
    PERCENT_RANK() OVER (ORDER BY ui.Reputation, COALESCE(es.total_bounty_offered, 0)) AS overall_percentile
FROM user_influence ui
LEFT OUTER JOIN engagement_scores es ON ui.Id = es.UserId
LEFT OUTER JOIN badge_diversity bd ON ui.Id = bd.UserId
LEFT OUTER JOIN post_metrics pm ON ui.Id = pm.OwnerUserId
WHERE (es.posts_voted_on > 100 OR ui.rep_rank <= 5000)
    AND (bd.unique_badges >= 3 OR ui.Reputation > 15000 OR bd.unique_badges IS NULL)
    AND NOT EXISTS (
        SELECT 1 FROM Votes v2 
        WHERE v2.UserId = ui.Id 
        AND v2.VoteTypeId IN (4, 12)
        GROUP BY v2.UserId 
        HAVING COUNT(*) > 50
    )
GROUP BY ui.Id, ui.DisplayName, ui.Reputation, ui.rep_rank, ui.net_votes, 
         es.posts_voted_on, es.upvotes_given, es.downvotes_given, 
         es.total_bounty_offered, bd.weighted_badge_score, bd.gold_badges
HAVING COUNT(DISTINCT pm.post_id) >= 5 OR ui.rep_rank <= 1000
ORDER BY ui.Reputation DESC, overall_percentile DESC
LIMIT 500;
