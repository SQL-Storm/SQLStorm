WITH high_reputation_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > 10000
),
active_posts AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.Tags, p.OwnerUserId,
           ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC) as rank_per_year
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56') - INTERVAL '5 years' AND p.Score > 0
),
top_tags AS (
    SELECT t.TagName, COUNT(*) as usage_count
    FROM Tags t
    WHERE t.Count > 100
    GROUP BY t.TagName
    HAVING COUNT(*) > 5
    ORDER BY usage_count DESC
    LIMIT 10
),
user_activity AS (
    SELECT u.Id as user_id,
           COUNT(DISTINCT ph.PostId) as edits_count,
           AVG((CAST(EXTRACT(EPOCH FROM ph.CreationDate) AS BIGINT) - CAST(EXTRACT(EPOCH FROM p.CreationDate) AS BIGINT)) / 86400.0) as avg_time_to_edit,
           COUNT(v.Id) as total_votes
    FROM Users u
    JOIN PostHistory ph ON ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6)
    JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (2,3)
    WHERE u.Reputation > 5000
    GROUP BY u.Id
    HAVING COUNT(DISTINCT ph.PostId) > 10
)
SELECT 
    ap.Title,
    ap.Score * 1.0 / NULLIF(ap.ViewCount, 0) as score_per_view,
    tt.TagName,
    u.DisplayName as owner_name,
    ua.edits_count,
    ua.total_votes,
    COUNT(DISTINCT c.Id) as comment_count,
    COUNT(DISTINCT pl.RelatedPostId) as linked_posts_count,
    AVG(COALESCE(v.BountyAmount, 0)) as avg_bounty_amount,
    CASE 
        WHEN ap.rank_per_year <= 10 THEN 'Top Ranked'
        WHEN ap.rank_per_year <= 50 THEN 'High Ranked'
        ELSE 'Other'
    END as popularity_tier
FROM active_posts ap
JOIN high_reputation_users u ON ap.OwnerUserId = u.Id
JOIN user_activity ua ON ua.user_id = u.Id
CROSS JOIN top_tags tt
LEFT JOIN Comments c ON c.PostId = ap.Id AND c.Score > 0
LEFT JOIN PostLinks pl ON pl.PostId = ap.Id AND pl.LinkTypeId = 1
LEFT JOIN Votes v ON v.PostId = ap.Id AND v.VoteTypeId = 8 AND v.BountyAmount > 0
WHERE POSITION(tt.TagName IN ap.Tags) > 0
    AND ap.rank_per_year <= 20
    AND ua.edits_count > 5
GROUP BY ap.Id, ap.Title, ap.Score, ap.ViewCount, tt.TagName, u.DisplayName, 
         ua.edits_count, ua.total_votes, ap.rank_per_year
HAVING COUNT(DISTINCT c.Id) > 2 
   AND (AVG(COALESCE(v.BountyAmount, 0)) IS NOT NULL OR COUNT(DISTINCT pl.RelatedPostId) > 1)
ORDER BY score_per_view DESC, ua.total_votes DESC
LIMIT 50;