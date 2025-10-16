-- {"query": "23070.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1113} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopVotedPosts AS (
    SELECT 
        v.PostId,
        COUNT(*) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        (COUNT(*) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) AS NetVotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
    HAVING COUNT(*) > 5
),
CorrelatedSubqueryExample AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        COALESCE((SELECT AVG(Score) FROM Comments c WHERE c.PostId = p.Id), 0) AS AvgCommentScore
    FROM Posts p
    WHERE EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 1)
),
CombinedData AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.Questions,
        ua.Answers,
        ua.AvgScore,
        ua.LastPostDate,
        ua.ReputationRank,
        bs.TotalBadges,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.BadgeNames,
        SUM(tvp.NetVotes) OVER (PARTITION BY ua.UserId) AS TotalNetVotes,
        RANK() OVER (ORDER BY ua.TotalPosts DESC) AS PostRank
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    LEFT JOIN Posts po ON ua.UserId = po.OwnerUserId
    LEFT JOIN TopVotedPosts tvp ON po.Id = tvp.PostId
    WHERE ua.Reputation > 1000
      AND (ua.LastPostDate > CURRENT_TIMESTAMP - INTERVAL '1 year' OR ua.TotalPosts > 50)
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalPosts, ua.Questions, ua.Answers, ua.AvgScore, ua.LastPostDate, ua.ReputationRank, bs.TotalBadges, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, bs.BadgeNames
)
SELECT 
    cd.*,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = cd.UserId) AND ph.PostHistoryTypeId IN (10, 11)) AS EditHistoryCount,
    CASE 
        WHEN cd.TotalBadges IS NULL THEN 'No Badges'
        ELSE CONCAT('Has ', cd.TotalBadges, ' Badges including ', cd.GoldBadges, ' Gold')
    END AS BadgeDescription,
    LAG(cd.Reputation) OVER (ORDER BY cd.ReputationRank) AS PreviousReputation
FROM CombinedData cd
UNION ALL
SELECT 
    NULL AS UserId,
    'Summary' AS DisplayName,
    SUM(Reputation) AS Reputation,
    SUM(TotalPosts) AS TotalPosts,
    SUM(Questions) AS Questions,
    SUM(Answers) AS Answers,
    AVG(AvgScore) AS AvgScore,
    MAX(LastPostDate) AS LastPostDate,
    NULL AS ReputationRank,
    SUM(TotalBadges) AS TotalBadges,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    NULL AS BadgeNames,
    SUM(TotalNetVotes) AS TotalNetVotes,
    NULL AS PostRank,
    NULL AS EditHistoryCount,
    'Total Summary' AS BadgeDescription,
    NULL AS PreviousReputation
FROM CombinedData
ORDER BY ReputationRank ASC NULLS LAST;
