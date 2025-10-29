-- {"query": "4119.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1493} 
WITH PostInteractions AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.FavoriteCount,
        p.CommentCount,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        COUNT(DISTINCT c.Id) AS CommentCountTotal,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId) AS UserLastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostNumberForUser
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.FavoriteCount, p.CommentCount, p.ViewCount, p.AnswerCount, p.ClosedDate, p.LastActivityDate
),
UserPostEngagement AS (
    SELECT
        pi.OwnerUserId,
        COUNT(DISTINCT pi.PostId) AS TotalPosts,
        SUM(pi.UpVoteCount) AS TotalUpVotes,
        SUM(pi.DownVoteCount) AS TotalDownVotes,
        SUM(pi.PostScore) AS TotalScore,
        AVG(pi.PostScore) AS AverageScore,
        SUM(pi.FavoriteCount) AS TotalFavorites,
        SUM(pi.CommentCount) AS TotalComments,
        COUNT(DISTINCT CASE WHEN pi.IsClosed = 1 THEN pi.PostId ELSE NULL END) AS ClosedPosts,
        SUM(pi.PostViewCount) AS TotalViews,
        AVG(pi.PostViewCount) AS AverageViews
    FROM PostInteractions pi
    WHERE pi.OwnerUserId IS NOT NULL
    GROUP BY pi.OwnerUserId
),
TopUsersByReputation AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        Views AS UserViews,
        UpVotes AS UserUpVotes,
        DownVotes AS UserDownVotes,
        CASE WHEN Location LIKE '%USA%' THEN 'USA' WHEN Location LIKE '%UK%' THEN 'UK' WHEN Location LIKE '%Canada%' THEN 'Canada' ELSE 'Other' END AS UserCountry
    FROM Users
    WHERE Reputation > 10000
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.UserDisplayName,
        ph.CreationDate AS HistoryCreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS HistoryRank
    FROM PostHistory ph
    WHERE ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
)
SELECT
    t.DisplayName AS UserName,
    t.Reputation,
    t.UserCountry,
    t.CreationDate AS UserCreationDate,
    t.UserViews,
    t.UserUpVotes,
    t.UserDownVotes,
    upe.TotalPosts,
    COALESCE(upe.TotalUpVotes, 0) AS UserTotalUpVotes,
    COALESCE(upe.TotalDownVotes, 0) AS UserTotalDownVotes,
    COALESCE(upe.TotalScore, 0) AS UserTotalScore,
    upe.AverageScore,
    COALESCE(upe.TotalFavorites, 0) AS UserTotalFavorites,
    COALESCE(upe.TotalComments, 0) AS UserTotalComments,
    COALESCE(upe.ClosedPosts, 0) AS UserClosedPosts,
    COALESCE(upe.TotalViews, 0) AS UserTotalViews,
    upe.AverageViews,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = t.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = t.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = t.Id AND b.Class = 3) AS BronzeBadges,
    MAX(pi.PostCreationDate) AS LastPostDate,
    COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.PostId ELSE NULL END) AS EditsMade, -- Edit Title
    COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.PostId ELSE NULL END) AS BodyEditsMade, -- Edit Body
    COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId = 10 THEN rph.PostId ELSE NULL END) AS PostsClosedByHistory,
    COUNT(DISTINCT CASE WHEN pi.PostNumberForUser = 1 THEN pi.PostId ELSE NULL END) AS FirstPostEverForUser
FROM TopUsersByReputation t
JOIN UserPostEngagement upe ON t.Id = upe.OwnerUserId
LEFT JOIN PostInteractions pi ON t.Id = pi.OwnerUserId AND pi.PostNumberForUser <= 5 -- Consider only the 5 most recent posts per user
LEFT JOIN RecentPostHistory rph ON pi.PostId = rph.PostId AND rph.HistoryRank = 1 -- Most recent history event for the post
WHERE upe.TotalPosts > 10 AND pi.PostCreationDate >= t.CreationDate -- Ensure interaction is after user creation
GROUP BY
    t.Id, t.DisplayName, t.Reputation, t.UserCountry, t.CreationDate, t.UserViews, t.UserUpVotes, t.UserDownVotes,
    upe.TotalPosts, upe.TotalUpVotes, upe.TotalDownVotes, upe.TotalScore, upe.AverageScore, upe.TotalFavorites,
    upe.TotalComments, upe.ClosedPosts, upe.TotalViews, upe.AverageViews
HAVING SUM(pi.PostScore) > 0 OR upe.TotalPosts > 50
ORDER BY t.Reputation DESC
LIMIT 100;