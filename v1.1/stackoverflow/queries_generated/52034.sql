-- {"query": "52034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 1020} 
WITH user_post_stats AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) AS TotalVotesReceived,
    COUNT(DISTINCT pb.Id) AS TotalBadges,
    COUNT(DISTINCT CASE WHEN pb.Class = 1 THEN pb.Id END) AS GoldBadges,
    MAX(p.LastActivityDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON u.Id = c.UserId
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3)
  LEFT JOIN Badges pb ON u.Id = pb.UserId
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_interactions AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.OwnerUserId,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenVotes,
    COUNT(DISTINCT pl.Id) AS LinkedPosts,
    COUNT(DISTINCT vc.Id) AS Upvotes,
    COUNT(DISTINCT vdc.Id) AS Downvotes,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN Votes vc ON p.Id = vc.PostId AND vc.VoteTypeId = 2
  LEFT JOIN Votes vdc ON p.Id = vdc.PostId AND vdc.VoteTypeId = 3
  GROUP BY p.Id, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount, p.OwnerUserId
),
top_posts AS (
  SELECT 
    pi.PostId,
    pi.Score,
    pi.ViewCount,
    pi.AnswerCount,
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    pi.HistoryCount,
    pi.CloseVotes,
    pi.ReopenVotes,
    pi.LinkedPosts,
    pi.Upvotes - pi.Downvotes AS NetVotes
  FROM post_interactions pi
  JOIN user_post_stats ups ON pi.OwnerUserId = ups.UserId
  WHERE pi.PostTypeId = 1
    AND pi.Score > 10
    AND pi.AnswerCount > 0
    AND pi.RankByScore <= 5
),
aggregated_stats AS (
  SELECT 
    UserId,
    DisplayName,
    Reputation,
    SUM(TotalPosts) AS TotalPosts,
    SUM(Questions) AS Questions,
    SUM(Answers) AS Answers,
    SUM(TotalScore) AS TotalScore,
    SUM(TotalComments) AS TotalComments,
    SUM(TotalVotesReceived) AS TotalVotesReceived,
    SUM(TotalBadges) AS TotalBadges,
    SUM(GoldBadges) AS GoldBadges,
    MAX(LastPostDate) AS LastActivity
  FROM user_post_stats
  GROUP BY UserId, DisplayName, Reputation
)
SELECT 
  ag.UserId,
  ag.DisplayName,
  ag.Reputation,
  ag.TotalPosts,
  ag.Questions,
  ag.Answers,
  ag.TotalScore,
  ag.TotalComments,
  ag.TotalVotesReceived,
  ag.TotalBadges,
  ag.GoldBadges,
  ag.LastActivity,
  COUNT(tp.PostId) AS HighScoreQuestions,
  SUM(tp.NetVotes) AS TotalNetVotesOnTopPosts,
  AVG(tp.AnswerCount) AS AvgAnswersOnTopPosts,
  STRING_AGG(DISTINCT tp.Score || ' (' || tp.ViewCount || ' views)', ', ') AS TopPostSummaries
FROM aggregated_stats ag
LEFT JOIN top_posts tp ON ag.UserId = tp.UserId
GROUP BY ag.UserId, ag.DisplayName, ag.Reputation, ag.TotalPosts, ag.Questions, ag.Answers, ag.TotalScore, ag.TotalComments, ag.TotalVotesReceived, ag.TotalBadges, ag.GoldBadges, ag.LastActivity
ORDER BY ag.Reputation DESC, ag.TotalScore DESC
LIMIT 100;