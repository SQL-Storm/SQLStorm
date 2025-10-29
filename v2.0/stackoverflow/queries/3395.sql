-- {"query": "3395.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2002}
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Views, 0) AS TotalViews,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVoteGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVoteGiven
    FROM Users u
),
PostScores AS (
    SELECT 
        p.OwnerUserId AS UserId,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.FavoriteCount,0) ELSE 0 END) AS TotalFavorites,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),
RecentActivity AS (
    SELECT 
        u.Id,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
),
CombinedRows AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.TotalViews,
        us.QuestionCount,
        us.AnswerCount,
        us.BadgeCount,
        us.UpVoteGiven,
        us.DownVoteGiven,
        COALESCE(ps.AvgPostScore, 0) AS AvgPostScore,
        COALESCE(ps.TotalFavorites, 0) AS TotalFavorites,
        ps.LastPostDate,
        ra.LastVoteDate,
        ra.LastCommentDate,
        ra.LastHistoryDate,
        CASE
            WHEN us.Reputation > 20000 THEN 'Legendary'
            WHEN us.Reputation > 10000 THEN 'Epic'
            WHEN us.Reputation > 5000  THEN 'Pro'
            ELSE 'Regular'
        END AS ReputationTier,
        CONCAT('User ', COALESCE(us.DisplayName, '[deleted]'), ' has ', COALESCE(CAST(us.BadgeCount AS VARCHAR), '0'), ' badges.') AS BadgeSummary,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS RepRank
    FROM UserStats us
    LEFT JOIN PostScores ps ON ps.UserId = us.Id
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
    WHERE us.Reputation IS NOT NULL
),
TotalsRow AS (
    SELECT
        CAST(NULL AS INTEGER) AS Id,
        'TOTAL' AS DisplayName,
        SUM(us.Reputation) AS Reputation,
        SUM(us.TotalViews) AS TotalViews,
        SUM(us.QuestionCount) AS QuestionCount,
        SUM(us.AnswerCount) AS AnswerCount,
        SUM(us.BadgeCount) AS BadgeCount,
        SUM(us.UpVoteGiven) AS UpVoteGiven,
        SUM(us.DownVoteGiven) AS DownVoteGiven,
        AVG(COALESCE(ps.AvgPostScore, 0)) AS AvgPostScore,
        SUM(COALESCE(ps.TotalFavorites,0)) AS TotalFavorites,
        MAX(ps.LastPostDate) AS LastPostDate,
        MAX(ra.LastVoteDate) AS LastVoteDate,
        MAX(ra.LastCommentDate) AS LastCommentDate,
        MAX(ra.LastHistoryDate) AS LastHistoryDate,
        CAST(NULL AS VARCHAR) AS ReputationTier,
        'Aggregated totals row.' AS BadgeSummary,
        CAST(NULL AS INTEGER) AS RepRank
    FROM UserStats us
    LEFT JOIN PostScores ps ON ps.UserId = us.Id
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
)
SELECT *
FROM (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        TotalViews,
        QuestionCount,
        AnswerCount,
        BadgeCount,
        UpVoteGiven,
        DownVoteGiven,
        AvgPostScore,
        TotalFavorites,
        LastPostDate,
        LastVoteDate,
        LastCommentDate,
        LastHistoryDate,
        ReputationTier,
        BadgeSummary,
        RepRank
    FROM CombinedRows
    UNION ALL
    SELECT
        Id,
        DisplayName,
        Reputation,
        TotalViews,
        QuestionCount,
        AnswerCount,
        BadgeCount,
        UpVoteGiven,
        DownVoteGiven,
        AvgPostScore,
        TotalFavorites,
        LastPostDate,
        LastVoteDate,
        LastCommentDate,
        LastHistoryDate,
        ReputationTier,
        BadgeSummary,
        RepRank
    FROM TotalsRow
) t
ORDER BY RepRank NULLS LAST;