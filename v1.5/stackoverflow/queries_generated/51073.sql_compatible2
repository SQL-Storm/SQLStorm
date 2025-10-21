WITH active_users AS (
    SELECT u.Id
    FROM Users u
    WHERE u.Reputation >= 100
      AND u.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
      AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month')
),
user_engagement AS (
    SELECT 
        au.Id as user_id,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        COUNT(DISTINCT v.Id) as total_votes_received,
        COUNT(DISTINCT CASE WHEN vt.Id = 2 THEN v.Id END) as upvotes_received,
        COUNT(DISTINCT CASE WHEN vt.Id = 3 THEN v.Id END) as downvotes_received,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as silver_badges,
        SUM(v.BountyAmount) as total_bounties_offered
    FROM active_users au
    LEFT JOIN Posts p ON p.OwnerUserId = au.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN Badges b ON b.UserId = au.Id
    GROUP BY au.Id
),
tag_engagement AS (
    SELECT 
        ue.user_id,
        t.TagName,
        COUNT(DISTINCT p.Id) as posts_with_tag,
        SUM(p.Score) as total_score_with_tag,
        AVG(p.Score) as avg_score_with_tag
    FROM user_engagement ue
    JOIN Posts p ON p.OwnerUserId = ue.user_id AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
            substring(p.Tags from 2 for length(p.Tags) - 2),
            '><'
        )) AS TagName
    ) AS tag_array
    JOIN Tags t ON t.TagName = tag_array.TagName
    GROUP BY ue.user_id, t.TagName
),
top_tags_per_user AS (
    SELECT 
        te.user_id,
        te.TagName,
        te.posts_with_tag,
        te.total_score_with_tag,
        ROW_NUMBER() OVER (PARTITION BY te.user_id ORDER BY te.total_score_with_tag DESC) as tag_rank
    FROM tag_engagement te
),
answer_quality AS (
    SELECT 
        ue.user_id,
        COUNT(DISTINCT CASE WHEN a.AcceptedAnswerId = a.Id THEN a.Id END) as accepted_answers,
        AVG(CASE WHEN a.ParentId IS NOT NULL THEN a.Score END) as avg_answer_score,
        COUNT(DISTINCT c.Id) as total_comments_on_answers,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id END) as answer_edits
    FROM user_engagement ue
    LEFT JOIN Posts q ON q.OwnerUserId = ue.user_id AND q.PostTypeId = 1
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = a.Id
    LEFT JOIN PostHistory ph ON ph.PostId = a.Id AND ph.UserId = ue.user_id
    GROUP BY ue.user_id
)
SELECT 
    u.DisplayName,
    u.Reputation,
    ue.post_count,
    ue.question_count,
    ue.answer_count,
    ue.total_score,
    ue.avg_score,
    ue.upvotes_received,
    ue.total_votes_received,
    ue.badge_count,
    ue.gold_badges,
    ue.silver_badges,
    aq.accepted_answers,
    aq.avg_answer_score,
    tt.TagName as top_tag,
    tt.total_score_with_tag as top_tag_score,
    te.posts_with_tag as top_tag_posts,
    ROW_NUMBER() OVER (ORDER BY ue.total_score DESC) as overall_rank,
    NTILE(10) OVER (ORDER BY u.Reputation DESC) as reputation_decile,
    CASE 
        WHEN ue.gold_badges >= 5 THEN 'Elite'
        WHEN ue.gold_badges >= 1 THEN 'Veteran'
        WHEN ue.silver_badges >= 3 THEN 'Experienced'
        ELSE 'Regular'
    END as user_tier
FROM active_users au
JOIN Users u ON u.Id = au.Id
JOIN user_engagement ue ON ue.user_id = au.Id
JOIN answer_quality aq ON aq.user_id = au.Id
JOIN top_tags_per_user tt ON tt.user_id = au.Id AND tt.tag_rank = 1
JOIN tag_engagement te ON te.user_id = au.Id AND te.TagName = tt.TagName
WHERE ue.post_count >= 5
  AND ue.question_count + ue.answer_count > 0
ORDER BY ue.total_score DESC, u.Reputation DESC
LIMIT 100;