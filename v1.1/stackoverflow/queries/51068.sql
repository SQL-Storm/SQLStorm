WITH active_users AS (
    SELECT u.Id, u.Reputation, u.CreationDate,
           COUNT(DISTINCT p.Id) AS question_count,
           COUNT(DISTINCT CASE WHEN pt.Id = 2 THEN p.Id END) AS answer_count,
           AVG(p.Score) AS avg_post_score
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE u.Reputation >= 100
      AND u.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
      AND p.PostTypeId IN (1, 2)
      AND p.Score > 0
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) >= 5
),
top_tags AS (
    SELECT t.TagName, t.Count,
           COUNT(DISTINCT SUBSTRING(p.Tags FROM 1 FOR LENGTH(p.Tags))) AS active_questions
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.Count > 100
      AND p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
    GROUP BY t.TagName, t.Count
    ORDER BY active_questions DESC
    LIMIT 50
),
user_engagement AS (
    SELECT au.Id AS user_id,
           SUM(au.question_count) AS total_questions,
           SUM(CASE WHEN au.question_count > 10 THEN 1 ELSE 0 END) AS prolific_questioners,
           AVG(v.BountyAmount) AS avg_bounty_given,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.PostId END) AS bounties_started
    FROM active_users au
    LEFT JOIN Votes v ON au.Id = v.UserId AND v.VoteTypeId = 8
    GROUP BY au.Id
),
tag_performance AS (
    SELECT tt.TagName,
           AVG(p.Score) AS avg_question_score,
           AVG(p.ViewCount) AS avg_views,
           COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 END) AS closed_count,
           COUNT(p.Id) AS total_questions,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.Score) AS p90_score
    FROM top_tags tt
    JOIN Posts p ON p.Tags LIKE '%' || tt.TagName || '%'
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months'
    GROUP BY tt.TagName
    HAVING COUNT(p.Id) >= 10
),
user_top_tag AS (
    SELECT p.OwnerUserId AS OwnerUserId,
           tt.TagName AS TagName,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(p.Id) DESC) AS rn
    FROM Posts p
    JOIN top_tags tt ON p.Tags LIKE '%' || tt.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tt.TagName
),
vote_counts AS (
    SELECT PostId, COUNT(*) AS upvote_count
    FROM Votes 
    WHERE VoteTypeId = 2
    GROUP BY PostId
),
badge_counts AS (
    SELECT UserId, 
           COUNT(CASE WHEN Class = 1 THEN 1 END) AS gold_count
    FROM Badges 
    WHERE Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY UserId
)
SELECT 
    ue.user_id,
    u.DisplayName,
    u.Reputation,
    ue.total_questions,
    ue.prolific_questioners,
    tp.TagName AS top_tag,
    tp.avg_question_score,
    tp.avg_views,
    tp.closed_count,
    tp.p90_score,
    COALESCE(vc.upvote_count, 0) AS total_upvotes_received,
    COALESCE(bc.gold_count, 0) AS gold_badges,
    ROUND(
        (tp.avg_question_score * ue.total_questions * 0.6 + 
         tp.avg_views * 0.3 + 
         (ue.total_questions - tp.closed_count) * 0.1), 2
    ) AS engagement_score
FROM user_engagement ue
JOIN Users u ON ue.user_id = u.Id
JOIN active_users au ON ue.user_id = au.Id
JOIN user_top_tag ut ON au.Id = ut.OwnerUserId AND ut.rn = 1
JOIN tag_performance tp ON ut.TagName = tp.TagName
LEFT JOIN LATERAL (
    SELECT vc.upvote_count, p.Id AS pid
    FROM vote_counts vc
    JOIN Posts p ON p.Id = vc.PostId
    WHERE p.OwnerUserId = ue.user_id AND p.PostTypeId = 1
    ORDER BY p.Id
    LIMIT 1
) vc ON true
LEFT JOIN badge_counts bc ON ue.user_id = bc.UserId
WHERE ue.total_questions > 0
ORDER BY engagement_score DESC, u.Reputation DESC
LIMIT 100;