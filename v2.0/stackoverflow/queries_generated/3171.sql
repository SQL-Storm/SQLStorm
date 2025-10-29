-- {"query": "3171.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2582} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagWikiContrib AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT t.Id) AS TagWikiCount
    FROM Posts p
    JOIN Tags t ON t.WikiPostId = p.Id
    WHERE p.PostTypeId IN (4,5)                 -- tag wiki excerpt or full wiki
    GROUP BY p.OwnerUserId
),
RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    COALESCE(bc.GoldBadges,0)    AS GoldBadges,
    COALESCE(bc.SilverBadges,0)  AS SilverBadges,
    COALESCE(bc.BronzeBadges,0)  AS BronzeBadges,
    COALESCE(twc.TagWikiCount,0) AS TagWikiContributions,
    COALESCE(rv.UpVotesGiven,0)   AS UpVotesGiven30d,
    COALESCE(rv.DownVotesGiven,0) AS DownVotesGiven30d,
    rv.LastVoteDate,
    ROW_NUMBER() OVER (
        PARTITION BY CASE WHEN us.Reputation >= 10000 THEN 'high' ELSE 'low' END
        ORDER BY us.TotalScore DESC
    ) AS RankWithinGroup,
    CASE
        WHEN us.Reputation >= 20000 THEN 'Elite'
        WHEN us.Reputation >= 10000 THEN 'Veteran'
        WHEN us.Reputation >= 5000  THEN 'Experienced'
        ELSE 'Novice'
    END AS ReputationTier,
    CONCAT('User ', us.Id, ': ', COALESCE(us.DisplayName, 'Anonymous')) AS UserLabel,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.UserId = us.Id
          AND c.CreationDate > us.LastPostDate
    ) AS RecentCommentCount,
    (
        SELECT MAX(ph.CreationDate)
        FROM PostHistory ph
        WHERE ph.UserId = us.Id
          AND ph.PostHistoryTypeId = 10                 -- post closed
    ) AS LastCloseVoteDate,
    (
        SELECT STRING_AGG(DISTINCT lt.Name, ', ')
        FROM PostLinks pl
        JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
        WHERE pl.PostId IN (
            SELECT p2.Id
            FROM Posts p2
            WHERE p2.OwnerUserId = us.Id
        )
          AND pl.CreationDate > CURRENT_DATE - INTERVAL '90 days'
    ) AS RecentLinkTypes
FROM UserStats us
LEFT JOIN BadgeCounts bc       ON bc.UserId = us.Id
LEFT JOIN TagWikiContrib twc   ON twc.UserId = us.Id
LEFT JOIN RecentVotes rv       ON rv.UserId = us.Id
WHERE (us.QuestionCount > 10 OR us.AnswerCount > 50)
  AND us.TotalScore IS NOT NULL
  AND us.TotalScore <> 0
  AND us.Location <> ''
UNION ALL
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.Location, 'Unknown') AS Location,
    0 AS QuestionCount,
    0 AS AnswerCount,
    0 AS TotalScore,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS TagWikiContributions,
    0 AS UpVotesGiven30d,
    0 AS DownVotesGiven30d,
    NULL AS LastVoteDate,
    NULL AS RankWithinGroup,
    'NoActivity' AS ReputationTier,
    CONCAT('User ', u.Id, ': ', COALESCE(u.DisplayName, 'Anonymous')) AS UserLabel,
    0 AS RecentCommentCount,
    NULL AS LastCloseVoteDate,
    NULL AS RecentLinkTypes
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation < 1000
ORDER BY Reputation DESC, TotalScore DESC
LIMIT 100;
