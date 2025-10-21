-- {"query": "52028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 619} 
WITH UserStats AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COUNT(DISTINCT p.Id) AS PostCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
           AVG(p.Score) AS AvgPostScore,
           SUM(p.ViewCount) AS TotalViews,
           SUM(p.AnswerCount) AS TotalAnswers,
           COUNT(DISTINCT c.Id) AS CommentCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT UserId,
           COUNT(*) AS TotalBadges,
           COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
VoteStats AS (
    SELECT UserId,
           COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
           COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
PostHistoryStats AS (
    SELECT UserId,
           COUNT(*) AS EditCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4,5,6) AND UserId IS NOT NULL
    GROUP BY UserId
)
SELECT us.Id, us.DisplayName, us.Reputation,
       us.PostCount, us.QuestionCount, us.AnswerCount,
       ROUND(us.AvgPostScore, 2) AS AvgPostScore,
       us.TotalViews, us.TotalAnswers, us.CommentCount,
       COALESCE(bs.TotalBadges, 0) AS TotalBadges,
       COALESCE(bs.GoldBadges, 0) AS GoldBadges,
       COALESCE(bs.SilverBadges, 0) AS SilverBadges,
       COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(vs.UpVotes, 0) AS UpVotes,
       COALESCE(vs.DownVotes, 0) AS DownVotes,
       COALESCE(phs.EditCount, 0) AS EditCount
FROM UserStats us
LEFT JOIN BadgeStats bs ON us.Id = bs.UserId
LEFT JOIN VoteStats vs ON us.Id = vs.UserId
LEFT JOIN PostHistoryStats phs ON us.Id = phs.UserId
WHERE us.Reputation > 1000 AND us.PostCount > 0
ORDER BY us.Reputation DESC, us.TotalViews DESC
LIMIT 1000;