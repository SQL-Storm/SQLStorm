-- {"query": "52076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 702} 
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
    WHERE ph.PostHistoryTypeId IN (4,5,6)  -- Edit types
    GROUP BY ph.PostId
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
    hs.AnswerCount AS HighScoreQAnswerCount,
    ls.LinkCount,
    hs2.EditCount,
    hs2.FirstEdit,
    hs2.LastEdit,
    CASE WHEN tu.RankByAnswers <= 10 THEN 'Top 10' ELSE 'Others' END AS RankGroup
FROM TopUsers tu
JOIN UserStats us ON tu.Id = us.Id
LEFT JOIN HighScoreQuestions hs ON hs.QuestionId IN (
    SELECT DISTINCT p.ParentId
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.OwnerUserId = tu.Id
)
LEFT JOIN LinkStats ls ON ls.PostId = tu.Id
LEFT JOIN HistoryStats hs2 ON hs2.PostId = tu.Id
ORDER BY tu.AnswerCount DESC, us.TotalScore DESC
LIMIT 50;