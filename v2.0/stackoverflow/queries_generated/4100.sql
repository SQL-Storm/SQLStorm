-- {"query": "4100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1270} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY DATE_TRUNC('month', u.CreationDate) ORDER BY u.Reputation DESC) AS MonthlyReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostInteractions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.Score) AS MaxScore,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate
),
UserPostPerformance AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.ReputationRank,
        rua.MonthlyReputationRank,
        pi.PostCount,
        pi.QuestionCount,
        pi.AnswerCount,
        COALESCE(SUM(pi.UpVoteCount), 0) AS TotalUpVotesReceived,
        COALESCE(SUM(pi.DownVoteCount), 0) AS TotalDownVotesReceived,
        COALESCE(SUM(pi.EditCount), 0) AS TotalEditsMade,
        COALESCE(AVG(pi.AvgScore), 0) AS AvgPostScore,
        COALESCE(SUM(pi.CommentCount), 0) AS TotalCommentsReceived
    FROM RankedUserActivity rua
    LEFT JOIN PostInteractions pi ON rua.UserId = pi.OwnerUserId
    GROUP BY
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.ReputationRank,
        rua.MonthlyReputationRank,
        pi.PostCount,
        pi.QuestionCount,
        pi.AnswerCount
)
SELECT
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.ReputationRank,
    upa.MonthlyReputationRank,
    upa.PostCount,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalUpVotesReceived,
    upa.TotalDownVotesReceived,
    upa.TotalEditsMade,
    upa.AvgPostScore,
    upa.TotalCommentsReceived,
    COALESCE(b.BadgeCount, 0) AS BronzeBadgeCount,
    COALESCE(s.BadgeCount, 0) AS SilverBadgeCount,
    COALESCE(g.BadgeCount, 0) AS GoldBadgeCount,
    CASE
        WHEN upa.AvgPostScore > 50 THEN 'High Performer'
        WHEN upa.TotalEditsMade > 10 AND upa.AnswerCount > upa.QuestionCount THEN 'Editor & Answerer'
        WHEN upa.ReputationRank <= 100 THEN 'Top Reputation User'
        WHEN upa.MonthlyReputationRank <= 5 THEN 'Rising Star (Monthly)'
        ELSE 'Standard Contributor'
    END AS UserTier,
    UPPER(CONCAT(SUBSTRING(upa.DisplayName, 1, 3), '_', LPAD(CAST(upa.UserId AS VARCHAR), 6, '0'))) AS Alias
FROM UserPostPerformance upa
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 3 GROUP BY UserId
) b ON upa.UserId = b.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 2 GROUP BY UserId
) s ON upa.UserId = s.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 1 GROUP BY UserId
) g ON upa.UserId = g.UserId
WHERE upa.Reputation > 1000 AND upa.PostCount > 5
ORDER BY upa.ReputationRank, upa.DisplayName;
