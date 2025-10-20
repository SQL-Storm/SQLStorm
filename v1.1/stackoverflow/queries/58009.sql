WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class IN (1, 2)) AS GoldSilverBadges
    FROM Users u
    WHERE u.Reputation > 10000 AND u.LastAccessDate >= (DATE '2024-10-01' - INTERVAL '1 year')
),
PostStats AS (
    SELECT p.OwnerUserId,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           AVG(p.Score) AS AvgPostScore,
           SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) / NULLIF(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS AvgAnswerCount,
           MAX(p.FavoriteCount) AS MaxFavoriteCount
    FROM Posts p
    WHERE p.CreationDate >= (DATE '2024-10-01' - INTERVAL '2 years')
    GROUP BY p.OwnerUserId
),
VoteAnalysis AS (
    SELECT v.UserId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpvotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownvotes,
           COUNT(DISTINCT v.PostId) AS UniqueVotedPosts
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= (DATE '2024-10-01' - INTERVAL '6 months')
    GROUP BY v.UserId
),
CommentEngagement AS (
    SELECT c.UserId,
           STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 50), ' || ') AS RecentCommentPreview,
           COUNT(*) AS TotalComments,
           AVG(CHAR_LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    WHERE c.CreationDate >= (DATE '2024-10-01' - INTERVAL '90 days')
    GROUP BY c.UserId
),
PostHistoryInsights AS (
    SELECT ph.UserId,
           COUNT(DISTINCT ph.PostId) AS EditedPosts,
           SUM(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END) AS ClosedPostsCount
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.CreationDate >= (DATE '2024-10-01' - INTERVAL '1 year')
    GROUP BY ph.UserId
),
TagExplode AS (
    SELECT p.Id AS PostId,
           TRIM(tgt) AS tag
    FROM Posts p,
         UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>')) AS tgt
    WHERE TRIM(tgt) <> '' AND p.PostTypeId = 1 AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '3 years')
),
TagExpertise AS (
    SELECT pt.OwnerUserId AS UserId, te.tag AS TagName, COUNT(*) AS TagUsage,
           RANK() OVER (PARTITION BY pt.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts pt
    JOIN TagExplode te ON te.PostId = pt.ParentId
    WHERE pt.PostTypeId = 2
    GROUP BY pt.OwnerUserId, te.tag
)
SELECT au.DisplayName,
       au.Reputation,
       ps.TotalPosts,
       va.TotalUpvotes,
       va.TotalDownvotes,
       ce.RecentCommentPreview,
       ph.EditedPosts,
       te.TagName AS TopTag,
       RANK() OVER (ORDER BY (COALESCE(va.TotalUpvotes,0) - COALESCE(va.TotalDownvotes,0)) DESC) AS EngagementRank,
       ps.AvgPostScore,
       ps.MaxFavoriteCount
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN VoteAnalysis va ON au.Id = va.UserId
LEFT JOIN CommentEngagement ce ON au.Id = ce.UserId
LEFT JOIN PostHistoryInsights ph ON au.Id = ph.UserId
LEFT JOIN TagExpertise te ON au.Id = te.UserId AND te.TagRank = 1
WHERE ps.TotalPosts > 50 AND COALESCE(va.UniqueVotedPosts, 0) > 100
ORDER BY EngagementRank, ps.AvgPostScore DESC, ps.MaxFavoriteCount DESC
LIMIT 100;