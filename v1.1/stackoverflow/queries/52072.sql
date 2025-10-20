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
    FROM Posts p,
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
TopUsers AS (
    SELECT us.Id, us.Reputation, us.QuestionCount, us.AvgQuestionScore,
           COALESCE(bs.GoldBadgeCount,0) AS GoldBadgeCount, COALESCE(bs.SilverBadgeCount,0) AS SilverBadgeCount, COALESCE(bs.TotalBadges,0) AS TotalBadges,
           COALESCE(vs.UpVotesReceived,0) AS UpVotesReceived, COALESCE(vs.DownVotesReceived,0) AS DownVotesReceived, COALESCE(vs.TotalBounties,0) AS TotalBounties,
           COALESCE(cs.CommentsPosted,0) AS CommentsPosted, cs.AvgCommentScore,
           COALESCE(phs.EditsMade,0) AS EditsMade
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON us.Id = bs.UserId
    LEFT JOIN VoteStats vs ON us.Id = vs.UserId
    LEFT JOIN CommentStats cs ON us.Id = cs.UserId
    LEFT JOIN PostHistoryStats phs ON us.Id = phs.UserId
    WHERE COALESCE(bs.GoldBadgeCount,0) > 10 AND us.Reputation > 100000
    ORDER BY us.Reputation DESC, COALESCE(bs.GoldBadgeCount,0) DESC
    LIMIT 20
)
SELECT tu.Id, tu.Reputation, tu.QuestionCount, tu.AvgQuestionScore,
       tu.GoldBadgeCount, tu.SilverBadgeCount, tu.TotalBadges,
       tu.UpVotesReceived, tu.DownVotesReceived, tu.TotalBounties,
       tu.CommentsPosted, tu.AvgCommentScore, tu.EditsMade,
       (SELECT STRING_AGG(ts.tag || ' (' || ts.TagUsage || ')', ', ' ORDER BY ts.TagUsage DESC)
        FROM TagStats ts 
        WHERE ts.OwnerUserId = tu.Id
        LIMIT 5) AS TopTags,
       ROW_NUMBER() OVER (ORDER BY tu.Reputation DESC) AS Rank
FROM TopUsers tu
ORDER BY Rank;