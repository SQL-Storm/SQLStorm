-- {"query": "4009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1057}
WITH UserPostCounts AS (
    SELECT
        ps.OwnerUserId,
        COUNT(ps.Id) AS PostCount,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(ps.Score) AS AvgPostScore,
        MAX(CASE WHEN pt.Name = 'Question' THEN ps.Score ELSE 0 END) AS MaxQuestionScore
    FROM Posts ps
    JOIN PostTypes pt ON ps.PostTypeId = pt.Id
    WHERE ps.OwnerUserId IS NOT NULL AND ps.OwnerUserId <> -1
    GROUP BY ps.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
HighReputationUsers AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        UpVotes,
        DownVotes,
        (UpVotes - DownVotes) AS NetVotes,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
    WHERE Reputation >= 10000
),
RecentPostActivity AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        LAG(p.LastActivityDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate) AS PreviousActivityDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
)
SELECT
    hr.DisplayName AS HighRepUserName,
    hr.Reputation AS HighRepUserReputation,
    COALESCE(upc.PostCount, 0) AS TotalPostsByHighRepUser,
    COALESCE(upc.QuestionCount, 0) AS QuestionsByHighRepUser,
    COALESCE(upc.AnswerCount, 0) AS AnswersByHighRepUser,
    COALESCE(ubc.TotalBadges, 0) AS TotalBadgesForHighRepUser,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    rpa.Title AS RecentActivityPostTitle,
    rpa.PostTypeName,
    rpa.PostCreationDate,
    rpa.LastActivityDate,
    rpa.Score AS PostScore,
    rpa.AnswerCount AS RecentPostAnswerCount,
    rpa.CommentCount AS RecentPostCommentCount,
    CASE
        WHEN rpa.LastActivityDate IS NULL THEN 'No Activity'
        WHEN (EXTRACT(EPOCH FROM (rpa.LastActivityDate - rpa.PreviousActivityDate)) / 86400) < 1 THEN 'Within 1 Day'
        WHEN (EXTRACT(EPOCH FROM (rpa.LastActivityDate - rpa.PreviousActivityDate)) / 86400) < 7 THEN 'Within 1 Week'
        ELSE 'More Than 1 Week'
    END AS ActivityFrequency,
    CASE
        WHEN hr.NetVotes > 0 THEN 'Positive Net Votes'
        WHEN hr.NetVotes < 0 THEN 'Negative Net Votes'
        ELSE 'Zero Net Votes'
    END AS UserNetVoteStatus,
    UPPER(SUBSTR(hr.DisplayName, 1, 3)) || '-' || CAST(hr.Id AS VARCHAR) AS UserIdentifier
FROM HighReputationUsers hr
LEFT JOIN UserPostCounts upc ON hr.Id = upc.OwnerUserId
LEFT JOIN UserBadgeCounts ubc ON hr.Id = ubc.UserId
LEFT JOIN RecentPostActivity rpa ON hr.Id = rpa.OwnerUserId AND rpa.LastActivityDate >= (CAST('2024-10-01' AS date) - INTERVAL '7 days')
WHERE hr.ReputationRank <= 100
GROUP BY
    hr.Id,
    hr.DisplayName,
    hr.Reputation,
    hr.NetVotes,
    upc.PostCount,
    upc.QuestionCount,
    upc.AnswerCount,
    ubc.TotalBadges,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    rpa.Title,
    rpa.PostTypeName,
    rpa.PostCreationDate,
    rpa.LastActivityDate,
    rpa.Score,
    rpa.AnswerCount,
    rpa.CommentCount,
    rpa.PreviousActivityDate
ORDER BY hr.Reputation DESC, rpa.LastActivityDate DESC;