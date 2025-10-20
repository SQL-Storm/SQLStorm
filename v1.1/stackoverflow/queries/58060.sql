WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > 10000
      AND u.LastAccessDate >= DATE '2024-10-01' - INTERVAL '180' DAY
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
SELECT au.DisplayName, au.Reputation,
       up.TotalPosts, up.AvgPostScore, up.MaxAnswerCount,
       uc.TotalComments, uc.AvgCommentScore, uc.CommentScore90th,
       va.UpvotesGiven, va.DownvotesGiven, va.UniqueVotedPosts,
       bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
       phi.EditedPosts, phi.ClosedPosts,
       RANK() OVER (ORDER BY au.Reputation DESC) AS GlobalRank,
       DENSE_RANK() OVER (PARTITION BY (CASE WHEN COALESCE(bs.GoldBadges,0) > 0 THEN 1 ELSE 0 END) ORDER BY COALESCE(up.TotalPosts,0) DESC) AS ActivityRank
FROM ActiveUsers au
LEFT JOIN UserPosts up ON au.Id = up.OwnerUserId
LEFT JOIN UserComments uc ON au.Id = uc.UserId
LEFT JOIN VoteAnalysis va ON au.Id = va.UserId
LEFT JOIN BadgeSummary bs ON au.Id = bs.UserId
LEFT JOIN PostHistoryInsights phi ON au.Id = phi.UserId
WHERE (COALESCE(up.TotalPosts,0) > 50 OR COALESCE(uc.TotalComments,0) > 100)
GROUP BY
  au.DisplayName, au.Reputation,
  up.TotalPosts, up.AvgPostScore, up.MaxAnswerCount,
  uc.TotalComments, uc.AvgCommentScore, uc.CommentScore90th,
  va.UpvotesGiven, va.DownvotesGiven, va.UniqueVotedPosts,
  bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
  phi.EditedPosts, phi.ClosedPosts
HAVING COALESCE(bs.GoldBadges,0) + COALESCE(bs.SilverBadges,0) + COALESCE(bs.BronzeBadges,0) > 10
ORDER BY au.Reputation DESC, up.TotalPosts DESC, uc.TotalComments DESC
LIMIT 100;