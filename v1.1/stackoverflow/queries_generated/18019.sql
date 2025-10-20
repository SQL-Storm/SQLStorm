-- {"query": "18019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1158} 

WITH RankedUserBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        b.Class AS BadgeClass,
        ROW_NUMBER() OVER(PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class IN (1, 2)
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN pt.Name IN ('Question', 'Answer') THEN p.Score ELSE 0 END) AS TotalScore,
        MAX(CASE WHEN pt.Name = 'Question' THEN p.CreationDate ELSE NULL END) AS LastQuestionDate,
        COUNT(DISTINCT p.Id) AS TotalPosts
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
RecentHighReputationUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalScore,
        ups.LastQuestionDate,
        COALESCE(ub.BadgeName, 'No High-Value Badge') AS TopBadgeName
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN RankedUserBadges ub ON u.Id = ub.UserId AND ub.rn = 1
    WHERE u.Reputation > 50000
      AND u.CreationDate > DATE('now', '-5 years')
),
QuestionsWithManyAnswers AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.AnswerCount,
        p.ViewCount,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER(ORDER BY p.AnswerCount DESC, p.Score DESC) AS RankByAnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.AnswerCount >= 10
      AND p.CreationDate > DATE('now', '-2 years')
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.UserId END) AS FavoriteUsers,
        MAX(p.LastActivityDate) AS LatestPostActivity
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate > DATE('now', '-10 years')
    GROUP BY u.Id, u.DisplayName
)
SELECT
    rhru.DisplayName AS UserDisplayName,
    rhru.Reputation,
    rhru.CreationDate AS UserCreationDate,
    rhru.QuestionCount,
    rhru.AnswerCount,
    rhru.TotalScore AS UserTotalScore,
    rhru.TopBadgeName,
    qma.Title AS PopularQuestionTitle,
    qma.AnswerCount AS QuestionAnswerCount,
    qma.ViewCount AS QuestionViewCount,
    uas.CommentCount,
    uas.UpVoteCount,
    uas.DownVoteCount,
    uas.FavoriteUsers,
    uas.LatestPostActivity,
    CASE
        WHEN rhru.UserTotalScore > 1000000 THEN 'Legendary'
        WHEN rhru.UserTotalScore > 500000 THEN 'Titan'
        WHEN rhru.UserTotalScore > 100000 THEN 'Hero'
        ELSE 'Valiant'
    END AS ReputationTier,
    IIF(uas.UpVoteCount > uas.DownVoteCount, 'Net Positive', 'Net Neutral/Negative') AS VoteBalance,
    COALESCE(rhru.LastQuestionDate, uas.LatestPostActivity, rhru.CreationDate) AS LastSignificantActivity
FROM RecentHighReputationUsers rhru
LEFT JOIN QuestionsWithManyAnswers qma ON rhru.Id = qma.OwnerUserId AND qma.RankByAnswerCount <= 5
LEFT JOIN UserActivitySummary uas ON rhru.Id = uas.UserId
WHERE rhru.Reputation BETWEEN 50001 AND 1000000
ORDER BY rhru.Reputation DESC, rhru.UserCreationDate ASC
LIMIT 100;
