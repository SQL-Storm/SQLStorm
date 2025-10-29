-- {"query": "4438.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1348}
WITH UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.AnswerCount) AS AvgAnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges AS b
    GROUP BY b.UserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes AS v
    JOIN VoteTypes AS vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserRecentActivity AS (
    SELECT
        u.Id AS UserId,
        MAX(CASE WHEN COALESCE(c.CreationDate, ph.CreationDate) > u.LastAccessDate THEN 1 ELSE 0 END) AS HasRecentActivitySinceLastAccess
    FROM Users AS u
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId NOT IN (1, 2, 3, 10, 11, 12, 13, 14, 15, 16, 19, 20, 35, 36, 50)
    GROUP BY u.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views AS ProfileViews,
    u.UpVotes AS GivenUpVotes,
    u.DownVotes AS GivenDownVotes,
    upa.PostCount,
    upa.TotalScore,
    upa.QuestionCount,
    upa.AnswerCount,
    CASE WHEN upa.PostCount > 0 THEN CAST(upa.TotalScore AS DOUBLE PRECISION) / upa.PostCount ELSE 0 END AS AvgPostScore,
    CASE WHEN upa.QuestionCount > 0 THEN CAST(upa.AnswerCount AS DOUBLE PRECISION) / upa.QuestionCount ELSE 0 END AS AnswerToQuestionRatio,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uvs.TotalVotes, 0) AS TotalVotesCast,
    COALESCE(uvs.UpVotes, 0) AS UpVotesCast,
    COALESCE(uvs.DownVotes, 0) AS DownVotesCast,
    ura.HasRecentActivitySinceLastAccess,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) AS AccountAgeDays,
    LOWER(SUBSTRING(u.DisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
    CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    CASE WHEN (u.AboutMe LIKE '%SQL%' OR u.AboutMe LIKE '%database%') THEN 1 ELSE 0 END AS AboutMeMentionsSQL,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, upa.TotalScore DESC) AS ReputationRank,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS NextReputation,
    SUM(upa.PostCount) OVER (ORDER BY u.Reputation ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativePostCount,
    CASE
        WHEN CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.LastAccessDate)) / 86400 AS INTEGER) < 30 THEN 'Active'
        WHEN CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.LastAccessDate)) / 86400 AS INTEGER) BETWEEN 30 AND 90 THEN 'Less Active'
        ELSE 'Inactive'
    END AS ActivityLevel,
    CASE WHEN EXISTS (SELECT 1 FROM Badges AS b WHERE b.UserId = u.Id AND b.Name LIKE '%Expert%') THEN 1 ELSE 0 END AS IsTagExpert
FROM Users AS u
LEFT JOIN UserPostActivity AS upa ON u.Id = upa.OwnerUserId
LEFT JOIN UserBadgeStats AS ubs ON u.Id = ubs.UserId
LEFT JOIN UserVoteSummary AS uvs ON u.Id = uvs.UserId
LEFT JOIN UserRecentActivity AS ura ON u.Id = ura.UserId
WHERE u.DisplayName IS NOT NULL
  AND u.CreationDate > TIMESTAMP '2010-01-01'
  AND (upa.PostCount IS NULL OR upa.PostCount > 5)
  AND u.Reputation > 1000
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    upa.PostCount,
    upa.TotalScore,
    upa.QuestionCount,
    upa.AnswerCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    uvs.TotalVotes,
    uvs.UpVotes,
    uvs.DownVotes,
    ura.HasRecentActivitySinceLastAccess,
    u.CreationDate,
    u.DisplayName,
    u.WebsiteUrl,
    u.AboutMe,
    u.LastAccessDate,
    upa.TotalScore
ORDER BY u.Reputation DESC, u.Id
LIMIT 100;