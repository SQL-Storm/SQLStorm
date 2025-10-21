-- {"query": "34001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1035} 

WITH RecentActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount, SUM(p.Score) AS TotalPostScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 500
      AND p.CreationDate >= current_date - interval '180 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
UserBadgeStats AS (
    SELECT b.UserId, 
           COUNT(*) AS BadgeCount,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           COUNT(DISTINCT b.Name) AS DistinctBadges
    FROM Badges b
    WHERE b.Date >= current_date - interval '365 days'
    GROUP BY b.UserId
),
TopTags AS (
    SELECT p.OwnerUserId as UserId, 
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
           COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- questions only
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= current_date - interval '365 days'
    GROUP BY p.OwnerUserId, TagName
),
TopUserTags AS (
    SELECT UserId, TagName, TagCount,
           RANK() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS RankInUser
    FROM TopTags
),
UserAnswerStats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(p.Id) AS AnswerCount,
           AVG(p.Score) AS AvgAnswerScore,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= current_date - interval '180 days'
    GROUP BY p.OwnerUserId
),
UserCloseVoteActions AS (
    SELECT ph.UserId, COUNT(*) AS CloseVoteCount,
           COUNT(DISTINCT ph.PostId) AS DistinctPostsClosed
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10  -- Post Closed
      AND ph.CreationDate >= current_date - interval '365 days'
    GROUP BY ph.UserId
)
SELECT rau.Id, rau.DisplayName, rau.Reputation, rau.PostCount, rau.TotalPostScore,
       COALESCE(ubs.BadgeCount, 0) AS BadgeCount,
       COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
       COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
       COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(ubs.DistinctBadges, 0) AS DistinctBadges,
       COALESCE(ans.AnswerCount, 0) AS AnswerCount,
       COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
       COALESCE(ans.UpVotes, 0) AS AnswerUpVotes,
       COALESCE(ans.DownVotes, 0) AS AnswerDownVotes,
       COALESCE(cc.CloseVoteCount, 0) AS CloseVoteCount,
       COALESCE(cc.DistinctPostsClosed, 0) AS DistinctPostsClosed,
       string_agg(DISTINCT tut.TagName, ', ') FILTER (WHERE tut.RankInUser <= 3) AS TopTags
FROM RecentActiveUsers rau
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = rau.Id
LEFT JOIN UserAnswerStats ans ON ans.UserId = rau.Id
LEFT JOIN UserCloseVoteActions cc ON cc.UserId = rau.Id
LEFT JOIN TopUserTags tut ON tut.UserId = rau.Id AND tut.RankInUser <= 3
GROUP BY rau.Id, rau.DisplayName, rau.Reputation, rau.PostCount, rau.TotalPostScore,
         ubs.BadgeCount, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.DistinctBadges,
         ans.AnswerCount, ans.AvgAnswerScore, ans.UpVotes, ans.DownVotes,
         cc.CloseVoteCount, cc.DistinctPostsClosed
ORDER BY rau.Reputation DESC, rau.PostCount DESC
LIMIT 50;
