-- {"query": "22033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1086} 
WITH UserActivity AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Location, 'Unknown') AS Location,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
           AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
           SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
           MAX(p.LastActivityDate) AS LastActive,
           STRING_AGG(DISTINCT LEFT(LOWER(REPLACE(REPLACE(p.Tags, '<', ''), '>', ',')), 50), '; ') FILTER (WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1) AS TagList
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate BETWEEN '2009-01-01' AND '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 0
),
BadgeSummary AS (
    SELECT b.UserId,
           COUNT(*) AS BadgeCount,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount,
           STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
VoteSummary AS (
    SELECT v.UserId,
           SUM(CASE WHEN vt.Id IN (2, 3) THEN 1 ELSE 0 END) AS TotalVotes,
           SUM(CASE WHEN vt.Id = 2 THEN 1 WHEN vt.Id = 3 THEN -1 ELSE 0 END) AS NetVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
CombinedStats AS (
    SELECT ua.Id,
           ua.DisplayName,
           ua.Reputation,
           ua.Location,
           ua.TotalPosts,
           ua.QuestionCount,
           ua.AnswerCount,
           ua.AvgPostScore,
           ua.TotalViews,
           ua.LastActive,
           ua.TagList,
           bs.BadgeCount,
           bs.GoldCount,
           bs.SilverCount,
           bs.BronzeCount,
           bs.BadgeNames,
           vs.TotalVotes,
           vs.NetVotes,
           (ua.Reputation * 0.1 + ua.TotalPosts * 0.2 + COALESCE(bs.BadgeCount, 0) * 0.3 + COALESCE(vs.NetVotes, 0) * 0.4) AS CustomScore
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON ua.Id = bs.UserId
    LEFT JOIN VoteSummary vs ON ua.Id = vs.UserId
    WHERE ua.Reputation > 100
),
RankedStats AS (
    SELECT cs.*,
           ROW_NUMBER() OVER (ORDER BY cs.CustomScore DESC) AS OverallRank,
           RANK() OVER (PARTITION BY cs.Location ORDER BY cs.Reputation DESC) AS LocationRank,
           NTILE(10) OVER (ORDER BY cs.TotalViews DESC) AS ViewDecile
    FROM CombinedStats cs
),
TopUsers AS (
    SELECT *
    FROM RankedStats
    WHERE OverallRank <= 100
    UNION ALL
    SELECT *
    FROM RankedStats
    WHERE LocationRank <= 5 AND Location != 'Unknown'
),
FilteredUsers AS (
    SELECT tu.*,
           CASE WHEN tu.LastActive < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' THEN 'Inactive' ELSE 'Active' END AS Status
    FROM TopUsers tu
    WHERE EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.UserId = tu.Id
        AND c.Score > 5
    ) OR EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = tu.Id
        AND p.AcceptedAnswerId IS NOT NULL
    )
)
SELECT fu.Id,
       fu.DisplayName,
       fu.Reputation,
       fu.Location,
       fu.TotalPosts,
       fu.QuestionCount,
       fu.AnswerCount,
       fu.AvgPostScore,
       fu.TotalViews,
       fu.LastActive,
       fu.TagList,
       fu.BadgeCount,
       fu.GoldCount,
       fu.SilverCount,
       fu.BronzeCount,
       fu.BadgeNames,
       fu.TotalVotes,
       fu.NetVotes,
       fu.CustomScore,
       fu.OverallRank,
       fu.LocationRank,
       fu.ViewDecile,
       fu.Status,
       (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = fu.Id) AS EditCount,
       CASE WHEN fu.NetVotes > 0 THEN 'Positive' WHEN fu.NetVotes < 0 THEN 'Negative' ELSE 'Neutral' END AS VoteStanding
FROM FilteredUsers fu
ORDER BY fu.CustomScore DESC, fu.Reputation DESC;