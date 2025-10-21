-- {"query": "52072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 706} 

WITH UserStats AS (
    SELECT u.Id, u.Reputation, COUNT(p.Id) AS QuestionCount, AVG(p.Score) AS AvgQuestionScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(p.Id) > 50
),
BadgeStats AS (
    SELECT b.UserId, COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
           COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteStats AS (
    SELECT v.UserId, COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBounties
    FROM Votes v
    GROUP BY v.UserId
),
CommentStats AS (
    SELECT c.UserId, COUNT(c.Id) AS CommentsPosted, AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
PostHistoryStats AS (
    SELECT ph.UserId, COUNT(ph.Id) AS EditsMade
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
),
TagStats AS (
    SELECT p.OwnerUserId, tag, COUNT(*) AS TagUsage
    FROM Posts p
    JOIN unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'')) AS tag ON true
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
TopUsers AS (
    SELECT us.Id, us.Reputation, us.QuestionCount, us.AvgQuestionScore,
           bs.GoldBadgeCount, bs.SilverBadgeCount, bs.TotalBadges,
           vs.UpVotesReceived, vs.DownVotesReceived, vs.TotalBounties,
           cs.CommentsPosted, cs.AvgCommentScore,
           phs.EditsMade
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON us.Id = bs.UserId
    LEFT JOIN VoteStats vs ON us.Id = vs.UserId
    LEFT JOIN CommentStats cs ON us.Id = cs.UserId
    LEFT JOIN PostHistoryStats phs ON us.Id = phs.UserId
    WHERE bs.GoldBadgeCount > 10 AND us.Reputation > 100000
    ORDER BY us.Reputation DESC, bs.GoldBadgeCount DESC
    LIMIT 20
)
SELECT tu.*,
       (SELECT STRING_AGG(ts.tag || ' (' || ts.TagUsage || ')', ', ') 
        FROM TagStats ts 
        WHERE ts.OwnerUserId = tu.Id 
        ORDER BY ts.TagUsage DESC LIMIT 5) AS TopTags,
       ROW_NUMBER() OVER (ORDER BY tu.Reputation DESC) AS Rank
FROM TopUsers tu
ORDER BY Rank;
