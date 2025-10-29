-- {"query": "4640.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1167} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        pht.Name AS EditType,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostContribution AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        SUM(p.CommentCount) AS TotalCommentsOnMyPosts,
        SUM(p.FavoriteCount) AS TotalFavoritesOnMyPosts,
        AVG(p.Score) AS AvgScoreOnMyPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserLatestEdits AS (
    SELECT
        rpe.UserId,
        MAX(rpe.EditDate) AS LatestEditDate,
        COUNT(DISTINCT rpe.PostId) AS DistinctPostsEdited
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
    GROUP BY rpe.UserId
),
UserVoteAnalysis AS (
    SELECT
        v.UserId,
        COUNT(DISTINCT v.PostId) AS PostsVotedOn,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesGiven,
        AVG(CASE WHEN vt.Name = 'UpMod' THEN p.Score ELSE NULL END) AS AvgScoreOfUpVotedPosts
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Posts p ON v.PostId = p.Id
    WHERE v.UserId IS NOT NULL AND vt.Name IN ('UpMod', 'DownMod')
    GROUP BY v.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(upc.TotalPosts, 0) AS TotalPostsOwned,
    COALESCE(upc.Questions, 0) AS QuestionsOwned,
    COALESCE(upc.Answers, 0) AS AnswersOwned,
    COALESCE(upc.TotalCommentsOnMyPosts, 0) AS TotalCommentsOnOwnedPosts,
    COALESCE(upc.TotalFavoritesOnMyPosts, 0) AS TotalFavoritesOnOwnedPosts,
    upc.AvgScoreOnMyPosts,
    COALESCE(ule.DistinctPostsEdited, 0) AS DistinctPostsEdited,
    ule.LatestEditDate,
    COALESCE(uva.PostsVotedOn, 0) AS PostsVotedOn,
    COALESCE(uva.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(uva.DownVotesGiven, 0) AS DownVotesGiven,
    uva.AvgScoreOfUpVotedPosts,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND LOWER(u.WebsiteUrl) LIKE '%stackoverflow.com%' THEN 'SO Internal'
        WHEN u.WebsiteUrl IS NOT NULL THEN 'External Link'
        ELSE 'No Website'
    END AS WebsiteType,
    SUBSTRING(u.AboutMe, 1, 50) AS AboutMeSnippet,
    CASE WHEN u.Views > 1000000 THEN 'Heavy Viewer' WHEN u.Views > 100000 THEN 'High Viewer' ELSE 'Standard Viewer' END AS ViewCategory
FROM Users u
LEFT JOIN UserPostContribution upc ON u.Id = upc.OwnerUserId
LEFT JOIN UserLatestEdits ule ON u.Id = ule.UserId
LEFT JOIN UserVoteAnalysis uva ON u.Id = uva.UserId
WHERE u.Id > 10000 -- Focus on more established users
  AND u.Reputation > 5000
  AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate > '2020-01-01')
ORDER BY u.Reputation DESC, u.Id
LIMIT 100;
