-- {"query": "58090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1196} 
WITH HighRepUsers AS (
    SELECT Id, DisplayName, Reputation, CreationDate
    FROM Users
    WHERE Reputation > 100000
), UserPosts AS (
    SELECT 
        p.OwnerUserId, 
        COUNT(p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.AnswerCount) AS TotalAnswersGenerated,
        STRING_AGG(DISTINCT pt.Name, ', ') AS PostTypes,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    JOIN HighRepUsers hru ON p.OwnerUserId = hru.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
), UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpvotesGiven,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownvotesGiven,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS FavoritesGiven
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    JOIN HighRepUsers hru ON v.UserId = hru.Id
    GROUP BY v.UserId
), UserBadges AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    JOIN HighRepUsers hru ON Badges.UserId = hru.Id
    GROUP BY UserId
), PostHistoryStats AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditedPosts,
        COUNT(CASE WHEN pht.Name = 'Post Closed' THEN 1 END) AS ClosedPosts,
        COUNT(CASE WHEN pht.Name = 'Post Migrated' THEN 1 END) AS MigratedPosts
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    JOIN HighRepUsers hru ON ph.UserId = hru.Id
    GROUP BY ph.UserId
)
SELECT 
    hru.Id,
    hru.DisplayName,
    hru.Reputation,
    hru.CreationDate AS UserJoinDate,
    up.TotalPosts,
    up.AvgPostScore,
    up.TotalAnswersGenerated,
    up.PostTypes,
    up.FirstPostDate,
    up.LastPostDate,
    uv.UpvotesGiven,
    uv.DownvotesGiven,
    uv.FavoritesGiven,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    phs.EditedPosts,
    phs.ClosedPosts,
    phs.MigratedPosts,
    RANK() OVER (ORDER BY hru.Reputation DESC) AS ReputationRank,
    DENSE_RANK() OVER (ORDER BY ub.GoldBadges DESC) AS GoldBadgeRank
FROM HighRepUsers hru
LEFT JOIN UserPosts up ON hru.Id = up.OwnerUserId
LEFT JOIN UserVotes uv ON hru.Id = uv.UserId
LEFT JOIN UserBadges ub ON hru.Id = ub.UserId
LEFT JOIN PostHistoryStats phs ON hru.Id = phs.UserId
WHERE up.TotalPosts > 100
ORDER BY hru.Reputation DESC, ub.GoldBadges DESC
LIMIT 100;