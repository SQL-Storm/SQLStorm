WITH cte_active_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
    FROM Users u
    WHERE u.LastAccessDate >= (DATE '2024-10-01' - INTERVAL '30' DAY)
),
cte_recent_posts AS (
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.LastActivityDate
    FROM Posts p
    WHERE p.CreationDate >= (DATE '2024-10-01' - INTERVAL '30' DAY)
),
cte_post_comments AS (
    SELECT c.Id, c.PostId, c.Score, c.CreationDate, c.UserId
    FROM Comments c
    JOIN cte_recent_posts rp ON c.PostId = rp.Id
),
cte_post_votes AS (
    SELECT v.Id, v.PostId, v.VoteTypeId, v.CreationDate, v.UserId
    FROM Votes v
    JOIN cte_recent_posts rp ON v.PostId = rp.Id
),
cte_post_history AS (
    SELECT ph.Id, ph.PostHistoryTypeId, ph.PostId, ph.CreationDate, ph.UserId, ph.Comment
    FROM PostHistory ph
    JOIN cte_recent_posts rp ON ph.PostId = rp.Id
)
SELECT
    au.DisplayName AS active_user_name,
    au.Reputation AS active_user_reputation,
    DATE_PART('day', (DATE '2024-10-01') - au.LastAccessDate) AS days_since_last_access,
    rp.Id AS recent_post_id,
    rp.PostTypeId AS recent_post_type,
    DATE_PART('day', (DATE '2024-10-01') - rp.CreationDate) AS days_since_post_creation,
    DATE_PART('day', (DATE '2024-10-01') - rp.LastActivityDate) AS days_since_last_post_activity,
    pc.Id AS post_comment_id,
    pc.Score AS post_comment_score,
    DATE_PART('day', (DATE '2024-10-01') - pc.CreationDate) AS days_since_comment_creation,
    pv.Id AS post_vote_id,
    pv.VoteTypeId AS post_vote_type,
    DATE_PART('day', (DATE '2024-10-01') - pv.CreationDate) AS days_since_vote_creation,
    ph.Id AS post_history_id,
    ph.PostHistoryTypeId AS post_history_type,
    ph.Comment AS post_history_comment,
    DATE_PART('day', (DATE '2024-10-01') - ph.CreationDate) AS days_since_history_creation
FROM cte_active_users au
LEFT JOIN cte_recent_posts rp ON au.Id = rp.OwnerUserId
LEFT JOIN cte_post_comments pc ON rp.Id = pc.PostId
LEFT JOIN cte_post_votes pv ON rp.Id = pv.PostId
LEFT JOIN cte_post_history ph ON rp.Id = ph.PostId
GROUP BY
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.LastAccessDate,
    rp.Id,
    rp.PostTypeId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    pc.Id,
    pc.PostId,
    pc.Score,
    pc.CreationDate,
    pc.UserId,
    pv.Id,
    pv.PostId,
    pv.VoteTypeId,
    pv.CreationDate,
    pv.UserId,
    ph.Id,
    ph.PostHistoryTypeId,
    ph.PostId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment
ORDER BY au.Reputation DESC, rp.LastActivityDate DESC, pc.CreationDate DESC, pv.CreationDate DESC, ph.CreationDate DESC;