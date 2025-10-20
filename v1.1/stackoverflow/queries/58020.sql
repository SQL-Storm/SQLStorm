WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate BETWEEN '2022-01-01' AND '2023-01-01'
      AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 100
), UserVotes AS (
    SELECT v.UserId, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    WHERE v.CreationDate BETWEEN '2022-01-01' AND '2023-01-01'
    GROUP BY v.UserId
), PostStats AS (
    SELECT p.OwnerUserId,
           AVG(p.Score) AS AvgPostScore,
           MAX(p.AnswerCount) AS MaxAnswers,
           SUM(p.FavoriteCount) AS TotalFavorites,
           RANK() OVER (ORDER BY SUM(p.ViewCount) DESC) AS ViewRank
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
), TagExperts AS (
    SELECT pt.OwnerUserId AS UserId, t.TagName, COUNT(*) AS TagPosts
    FROM Posts p
    JOIN Posts pt ON p.ParentId = pt.Id
    JOIN Tags t ON (
        -- extract first tag from a tags string like '<tag1><tag2>'
        SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2) IS NOT NULL
        AND SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><', 1) = t.TagName
    )
    WHERE p.PostTypeId = 2 AND pt.PostTypeId = 1
    GROUP BY pt.OwnerUserId, t.TagName
    HAVING COUNT(*) > 50
)
SELECT au.DisplayName, au.Reputation, uv.Upvotes, uv.Downvotes,
       ps.AvgPostScore, ps.MaxAnswers, ps.TotalFavorites, ps.ViewRank,
       te.TagName, te.TagPosts,
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = au.Id AND b.Class = 1) AS GoldBadges,
       (SELECT COUNT(*) FROM PostHistory ph 
        WHERE ph.UserId = au.Id 
          AND ph.PostHistoryTypeId IN (5, 6, 7, 8, 9)) AS EditActions,
       au.Id
FROM ActiveUsers au
JOIN UserVotes uv ON au.Id = uv.UserId
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN TagExperts te ON au.Id = te.UserId
WHERE au.Reputation > 10000
GROUP BY au.Id, au.DisplayName, au.Reputation, uv.UserId, uv.Upvotes, uv.Downvotes,
         ps.OwnerUserId, ps.AvgPostScore, ps.MaxAnswers, ps.TotalFavorites, ps.ViewRank,
         te.UserId, te.TagName, te.TagPosts
ORDER BY ps.ViewRank, uv.Upvotes DESC, ps.TotalFavorites DESC
LIMIT 1000;