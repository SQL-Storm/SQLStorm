WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE 0 END) AS TotalScore,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopUsers AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.AnswerCount,
        RANK() OVER (ORDER BY us.AnswerCount DESC) AS RankByAnswers
    FROM UserStats us
    WHERE us.AnswerCount > 100
),
HighScoreQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        COUNT(DISTINCT a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.Score > 50
    GROUP BY p.Id, p.Title, p.Score
),
LinkStats AS (
    SELECT 
        pl.PostId,
        COUNT(*) AS LinkCount,
        MAX(pl.CreationDate) AS LatestLinkDate
    FROM PostLinks pl
    GROUP BY pl.PostId
),
HistoryStats AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        MIN(ph.CreationDate) AS FirstEdit,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.PostId
),
UserAnsweredQuestionParents AS (
    SELECT DISTINCT p.OwnerUserId AS UserId, p.ParentId
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.ParentId IS NOT NULL
)
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.AnswerCount,
    us.QuestionCount,
    us.TotalScore,
    us.VoteCount,
    us.CommentCount,
    us.BadgeCount,
    COALESCE(hs.AnswerCount, 0) AS HighScoreQAnswerCount,
    COALESCE(ls.LinkCount, 0) AS LinkCount,
    COALESCE(hs2.EditCount, 0) AS EditCount,
    hs2.FirstEdit,
    hs2.LastEdit,
    CASE WHEN tu.RankByAnswers <= 10 THEN 'Top 10' ELSE 'Others' END AS RankGroup
FROM TopUsers tu
JOIN UserStats us ON tu.Id = us.Id
LEFT JOIN UserAnsweredQuestionParents uaqp ON uaqp.UserId = tu.Id
LEFT JOIN HighScoreQuestions hs ON hs.QuestionId = uaqp.ParentId
LEFT JOIN LinkStats ls ON ls.PostId = tu.Id
LEFT JOIN HistoryStats hs2 ON hs2.PostId = tu.Id
GROUP BY
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.AnswerCount,
    us.QuestionCount,
    us.TotalScore,
    us.VoteCount,
    us.CommentCount,
    us.BadgeCount,
    hs.AnswerCount,
    ls.LinkCount,
    hs2.EditCount,
    hs2.FirstEdit,
    hs2.LastEdit,
    tu.RankByAnswers
ORDER BY tu.AnswerCount DESC, us.TotalScore DESC
LIMIT 50;