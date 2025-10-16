WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        u.Reputation,
        (u.UpVotes - u.DownVotes) * 1.0 / NULLIF(u.UpVotes + u.DownVotes, 0) AS VoteRatio,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
), PostActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(COALESCE(p.FavoriteCount,0)) AS TotalFavorites,
        STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL THEN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2) END, '; ') AS AllTags
    FROM Posts p
    WHERE p.CreationDate >= DATE '2020-01-01'
    GROUP BY p.OwnerUserId
), VoteSummary AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.PostId END) AS BountyPosts
    FROM Votes v
    GROUP BY v.UserId
), ClosedPosts AS (
    SELECT 
        ph.UserId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedCount,
        MAX(ph.CreationDate) OVER (PARTITION BY ph.UserId) AS LastCloseDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId, ph.CreationDate
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Location,
    us.Reputation,
    us.VoteRatio,
    us.GoldBadges,
    pa.TotalPosts,
    pa.Questions,
    pa.TotalFavorites,
    vs.Upvotes,
    vs.Downvotes,
    vs.BountyPosts,
    cp.ClosedCount,
    cp.LastCloseDate,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, vs.Upvotes DESC) AS OverallRank,
    CASE 
        WHEN us.Reputation > 100000 THEN 'Legendary' 
        WHEN us.Reputation BETWEEN 50000 AND 100000 THEN 'Epic'
        ELSE 'Regular'
    END AS ReputationTier,
    COALESCE(pa.AllTags, 'No Tags') AS TagHistory,
    us.ReputationRank
FROM UserStats us
LEFT JOIN PostActivity pa ON us.Id = pa.OwnerUserId
LEFT JOIN VoteSummary vs ON us.Id = vs.UserId
LEFT JOIN ClosedPosts cp ON us.Id = cp.UserId
WHERE (us.GoldBadges > 0 
    OR EXISTS (
        SELECT 1 
        FROM Badges b 
        WHERE b.UserId = us.Id 
        AND b.Name LIKE '%Moderator%'
    ))
    AND (COALESCE(vs.BountyPosts,0) > 0 OR COALESCE(pa.TotalFavorites,0) > 100)
    AND us.VoteRatio BETWEEN -1 AND 1
    AND COALESCE(pa.Questions,0) > 10
ORDER BY 
    us.ReputationRank, 
    OverallRank, 
    vs.Upvotes DESC
FETCH FIRST 100 ROWS ONLY;