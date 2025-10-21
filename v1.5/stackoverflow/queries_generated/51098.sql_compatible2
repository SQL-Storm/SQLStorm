WITH top_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rank
    FROM Users u
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
      AND u.Reputation > 1000
    LIMIT 50
),
user_activity AS (
    SELECT tu.Id as user_id,
           COUNT(DISTINCT p.Id) as post_count,
           SUM(p.Score) as total_score,
           AVG(p.Score) as avg_score,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count
    FROM top_users tu
    JOIN Posts p ON p.OwnerUserId = tu.Id 
               OR (p.OwnerUserId IS NULL AND p.OwnerDisplayName = tu.DisplayName)
    WHERE p.CreationDate >= TIMESTAMP '2020-01-01'
      AND p.Score IS NOT NULL
    GROUP BY tu.Id
),
tag_stats AS (
    SELECT t.Id as tag_id, t.TagName,
           COUNT(DISTINCT p.Id) as usage_count,
           AVG(p.Score) as avg_question_score,
           (SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) * 100.0) / COUNT(DISTINCT p.Id) as acceptance_rate
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1 
               AND (p.Tags LIKE '%' || t.TagName || '%'
                 OR p.Tags LIKE '%' || t.TagName || '><%'
                 OR p.Tags LIKE '%><' || t.TagName || '%'
                 OR p.Tags LIKE '%><' || t.TagName || '>')
    WHERE p.CreationDate >= TIMESTAMP '2020-01-01'
      AND t.Count > 10
    GROUP BY t.Id, t.TagName
    HAVING COUNT(DISTINCT p.Id) > 5
),
high_impact_posts AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate,
           p.OwnerUserId, p.Tags,
           ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC, p.Score DESC) as yearly_rank,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_post_score
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= TIMESTAMP '2020-01-01'
      AND p.ViewCount > 1000
      AND p.Score >= 10
),
user_tag_affinity AS (
    SELECT ua.user_id,
           ts.tag_id,
           ts.tagname,
           COUNT(DISTINCT hp.Id) as posts_in_tag,
           AVG(hp.score) as avg_score_in_tag,
           (COUNT(DISTINCT hp.Id) * 1.0 / ua.post_count) * 100 as affinity_percentage
    FROM user_activity ua
    JOIN high_impact_posts hp ON hp.OwnerUserId = ua.user_id
    JOIN tag_stats ts ON (hp.Tags LIKE '%' || ts.TagName || '%')
    WHERE hp.yearly_rank <= 100
    GROUP BY ua.user_id, ts.tag_id, ts.tagname, ua.post_count
    HAVING COUNT(DISTINCT hp.Id) >= 3
),
engagement_metrics AS (
    SELECT v.PostId,
           COUNT(DISTINCT v.Id) as total_votes,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as upvotes,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as downvotes,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as favorites,
           AVG(EXTRACT(EPOCH FROM v.CreationDate)) as avg_vote_time
    FROM Votes v
    WHERE v.CreationDate >= TIMESTAMP '2020-01-01'
      AND v.VoteTypeId IN (2, 3, 5)
    GROUP BY v.PostId
    HAVING COUNT(DISTINCT v.Id) > 10
),
comment_activity AS (
    SELECT c.PostId,
           COUNT(c.Id) as comment_count,
           AVG(c.Score) as avg_comment_score,
           STRING_AGG(c.Text, ' | ') as sample_comments
    FROM Comments c
    WHERE c.CreationDate >= TIMESTAMP '2020-01-01'
      AND c.Score >= 0
    GROUP BY c.PostId
    HAVING COUNT(c.Id) > 5
)
SELECT 
    tu.DisplayName as user_name,
    tu.rank,
    ua.post_count,
    ua.answer_count,
    ua.question_count,
    ua.total_score,
    ROUND(ua.avg_score, 2) as avg_post_score,
    COALESCE(uta.affinity_percentage, 0) as top_tag_affinity,
    COALESCE(uta.tagname, 'N/A') as top_tag,
    COALESCE(hip.ViewCount, 0) as top_post_views,
    COALESCE(hip.Title, 'N/A') as top_post_title,
    COALESCE(em.total_votes, 0) as votes_on_top_post,
    COALESCE(ca.comment_count, 0) as comments_on_top_post,
    ROUND(
        (COALESCE(hip.Score, 0) + 
         COALESCE(em.upvotes, 0) - 
         COALESCE(em.downvotes, 0) * 2 +
         COALESCE(ca.comment_count, 0)) * 1.0 / 
        GREATEST(ua.post_count, 1), 2
    ) as engagement_index,
    CASE 
        WHEN ua.answer_count > ua.question_count * 2 THEN 'Answerer'
        WHEN ua.question_count > ua.answer_count * 2 THEN 'Questioner'
        ELSE 'Balanced'
    END as user_type,
    RANK() OVER (ORDER BY 
        (ua.total_score * 0.4 + 
         COALESCE(hip.ViewCount, 0) * 0.3 + 
         COALESCE(em.total_votes, 0) * 0.2 + 
         COALESCE(ua.answer_count, 0) * 0.1) DESC
    ) as overall_impact_rank
FROM top_users tu
JOIN user_activity ua ON ua.user_id = tu.Id
LEFT JOIN user_tag_affinity uta ON uta.user_id = tu.Id 
    AND uta.affinity_percentage = (
        SELECT MAX(affinity_percentage) 
        FROM user_tag_affinity uta2 
        WHERE uta2.user_id = tu.Id
    )
LEFT JOIN high_impact_posts hip ON hip.OwnerUserId = tu.Id 
    AND hip.yearly_rank = 1
    AND EXTRACT(YEAR FROM hip.CreationDate) = EXTRACT(YEAR FROM DATE '2024-10-01')
LEFT JOIN engagement_metrics em ON em.PostId = hip.Id
LEFT JOIN comment_activity ca ON ca.PostId = hip.Id
WHERE tu.rank <= 25
ORDER BY overall_impact_rank
LIMIT 20;