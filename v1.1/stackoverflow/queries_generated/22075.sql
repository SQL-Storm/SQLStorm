-- {"query": "22075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1108} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Views, 0) AS ProfileViews,
        COUNT(p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        STRING_AGG(DISTINCT t.TagName, ', ') AS AssociatedTags
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT OUTER JOIN UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS t(TagName) ON p.Tags IS NOT NULL
    WHERE u.CreationDate > '2010-01-01'::timestamp
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        STRING_AGG(b.Name, '; ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
VoteStats AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountiesStarted
    FROM Votes v
    GROUP BY v.UserId
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
RankedUsers AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.ProfileViews,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgPostScore,
        us.AssociatedTags,
        bs.BadgeCount,
        bs.GoldBadges,
        bs.BadgeNames,
        vs.UpVotesReceived,
        vs.DownVotesReceived,
        vs.TotalBountiesStarted,
        cs.CommentCount,
        cs.LastCommentDate,
        (us.QuestionCount * 10 + us.AnswerCount * 5 + bs.BadgeCount * 2 + vs.UpVotesReceived - vs.DownVotesReceived) AS ComputedScore,
        RANK() OVER (ORDER BY (us.QuestionCount * 10 + us.AnswerCount * 5 + bs.BadgeCount * 2 + vs.UpVotesReceived - vs.DownVotesReceived) DESC) AS ScoreRank,
        CASE 
            WHEN us.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'High Reputation'
            WHEN us.Reputation BETWEEN 100 AND (SELECT AVG(Reputation) FROM Users) THEN 'Medium Reputation'
            ELSE 'Low Reputation'
        END AS ReputationCategory
    FROM UserStats us
    LEFT OUTER JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT OUTER JOIN VoteStats vs ON us.UserId = vs.UserId
    LEFT OUTER JOIN CommentStats cs ON us.UserId = cs.UserId
    WHERE us.QuestionCount > 0
),
TopUsers AS (
    SELECT * 
    FROM RankedUsers 
    WHERE ScoreRank <= 100
    UNION ALL
    SELECT ru.*
    FROM RankedUsers ru
    INNER JOIN (
        SELECT DISTINCT UserId 
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
        AND EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
        )
    ) linked ON ru.UserId = linked.UserId
    AND ru.ScoreRank > 100
),
FinalStats AS (
    SELECT 
        tu.*,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.UserId = tu.UserId 
         AND c.CreationDate > CURRENT_DATE - INTERVAL '30 days') AS RecentComments,
        ROW_NUMBER() OVER (ORDER BY tu.ComputedScore DESC, tu.Reputation DESC) AS FinalRank
    FROM TopUsers tu
    WHERE tu.LastCommentDate IS NOT NULL 
    OR tu.BadgeCount > 5
)
SELECT 
    fs.FinalRank,
    fs.DisplayName,
    fs.Reputation,
    fs.ReputationCategory,
    fs.ProfileViews,
    fs.QuestionCount,
    fs.AnswerCount,
    fs.AvgPostScore,
    fs.AssociatedTags,
    fs.BadgeCount,
    fs.GoldBadges,
    fs.BadgeNames,
    fs.UpVotesReceived,
    fs.DownVotesReceived,
    fs.TotalBountiesStarted,
    fs.CommentCount,
    fs.LastCommentDate,
    fs.RecentComments,
    fs.ComputedScore
FROM FinalStats fs
ORDER BY fs.FinalRank
LIMIT 50;