WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > 10000
      AND u.LastAccessDate >= cast('2024-10-01' as date) - INTERVAL '180 days'
),
UserPosts AS (
    SELECT p.OwnerUserId, COUNT(DISTINCT p.Id) AS TotalPosts,
           AVG(p.Score) AS AvgPostScore, MAX(p.AnswerCount) AS MaxAnswerCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id AND pt.Name IN ('Question', 'Answer')
    GROUP BY p.OwnerUserId
),
UserComments AS (
    SELECT c.UserId, COUNT(*) AS TotalComments,
           AVG(c.Score) AS AvgCommentScore,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY c.Score) AS CommentScore90th
    FROM Comments c
    GROUP BY c.UserId
),
VoteAnalysis AS (
    SELECT v.UserId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpvotesGiven,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownvotesGiven,
           COUNT(DISTINCT v.PostId) AS UniqueVotedPosts
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod')
    GROUP BY v.UserId
),
BadgeSummary AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostHistoryInsights AS (
    SELECT ph.UserId,
           COUNT(DISTINCT CASE WHEN pht.Name IN ('Edit Title', 'Edit Body', 'Edit Tags') THEN ph.PostId END) AS EditedPosts,
           COUNT(DISTINCT CASE WHEN pht.Name = 'Post Closed' THEN ph.PostId END) AS ClosedPosts
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    GROUP BY ph.UserId
)
SELECT au.DisplayName,
       au.Reputation,
       COALESCE(up.TotalPosts, 0) AS TotalPosts,
       COALESCE(up.AvgPostScore, 0) AS AvgPostScore,
       COALESCE(up.MaxAnswerCount, 0) AS MaxAnswerCount,
       COALESCE(uc.TotalComments, 0) AS TotalComments,
       COALESCE(uc.AvgCommentScore, 0) AS AvgCommentScore,
       COALESCE(uc.CommentScore90th, 0) AS CommentScore90th,
       COALESCE(va.UpvotesGiven, 0) AS UpvotesGiven,
       COALESCE(va.DownvotesGiven, 0) AS DownvotesGiven,
       COALESCE(va.UniqueVotedPosts, 0) AS UniqueVotedPosts,
       COALESCE(bs.GoldBadges, 0) AS GoldBadges,
       COALESCE(bs.SilverBadges, 0) AS SilverBadges,
       COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(phi.EditedPosts, 0) AS EditedPosts,
       COALESCE(phi.ClosedPosts, 0) AS ClosedPosts,
       RANK() OVER (ORDER BY au.Reputation DESC) AS GlobalRank,
       DENSE_RANK() OVER (ORDER BY COALESCE(up.TotalPosts, 0) DESC) AS ActivityRank
FROM ActiveUsers au
LEFT JOIN UserPosts up ON au.Id = up.OwnerUserId
LEFT JOIN UserComments uc ON au.Id = uc.UserId
LEFT JOIN VoteAnalysis va ON au.Id = va.UserId
LEFT JOIN BadgeSummary bs ON au.Id = bs.UserId
LEFT JOIN PostHistoryInsights phi ON au.Id = phi.UserId
WHERE COALESCE(up.TotalPosts, 0) > 50 OR COALESCE(uc.TotalComments, 0) > 100
AND (COALESCE(bs.GoldBadges, 0) + COALESCE(bs.SilverBadges, 0) + COALESCE(bs.BronzeBadges, 0)) > 10
ORDER BY au.Reputation DESC, COALESCE(up.TotalPosts, 0) DESC, COALESCE(uc.TotalComments, 0) DESC
LIMIT 100;