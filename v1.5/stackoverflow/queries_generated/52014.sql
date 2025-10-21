-- {"query": "52014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 770} 
WITH PostVotes AS (
  SELECT PostId,
         COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
         COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotesReceived
  FROM Votes
  GROUP BY PostId
),
UserPosts AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(*) AS TotalPosts,
         SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
         SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
         AVG(p.Score) AS AvgPostScore,
         SUM(pv.UpVotesReceived) AS TotalUpVotesReceived,
         SUM(pv.DownVotesReceived) AS TotalDownVotesReceived
  FROM Posts p
  LEFT JOIN PostVotes pv ON p.Id = pv.PostId
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
UserComments AS (
  SELECT UserId,
         COUNT(*) AS CommentCount
  FROM Comments
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
UserBadges AS (
  SELECT UserId,
         COUNT(*) AS BadgeCount,
         COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
         COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
         COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
UserVotes AS (
  SELECT v.UserId,
         COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesCast,
         COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesCast
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.UserId IS NOT NULL
  GROUP BY v.UserId
),
UserActivity AS (
  SELECT u.Id,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
  FROM Users u
)
SELECT ua.Rank, u.Id, u.DisplayName, u.Reputation, u.CreationDate,
       COALESCE(up.TotalPosts, 0) AS TotalPosts,
       COALESCE(up.QuestionCount, 0) AS QuestionCount,
       COALESCE(up.AnswerCount, 0) AS AnswerCount,
       COALESCE(up.AvgPostScore, 0) AS AvgPostScore,
       COALESCE(up.TotalUpVotesReceived, 0) AS TotalUpVotesReceived,
       COALESCE(up.TotalDownVotesReceived, 0) AS TotalDownVotesReceived,
       COALESCE(uc.CommentCount, 0) AS CommentCount,
       COALESCE(ub.BadgeCount, 0) AS BadgeCount,
       COALESCE(ub.GoldBadges, 0) AS GoldBadges,
       COALESCE(ub.SilverBadges, 0) AS SilverBadges,
       COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(uv.UpVotesCast, 0) AS UpVotesCast,
       COALESCE(uv.DownVotesCast, 0) AS DownVotesCast
FROM Users u
JOIN UserActivity ua ON u.Id = ua.Id AND ua.Rank <= 1000
LEFT JOIN UserPosts up ON u.Id = up.UserId
LEFT JOIN UserComments uc ON u.Id = uc.UserId
LEFT JOIN UserBadges ub ON u.Id = ub.UserId
LEFT JOIN UserVotes uv ON u.Id = uv.UserId
ORDER BY ua.Rank;