-- {"query": "34095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1239} 

WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(COALESCE(p.Score,0)) AS AvgPostScore,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate))/86400) AS AccountAgeDays
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rnk
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.Score >= 10
),
TopAnswers AS (
    SELECT
        a.Id,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        q.Title AS QuestionTitle,
        a.CreationDate,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS UpVotesCount
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
        AND a.Score >= 5
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.CreationDate AS QuestionCreation,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.CreationDate
    HAVING COUNT(a.Id) > 0
),
PostHistoryEdits AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - lag_ph.CreationDate))/3600) AS AvgHoursBetweenEdits
    FROM PostHistory ph
    LEFT JOIN PostHistory lag_ph ON lag_ph.PostId = ph.PostId AND lag_ph.Id = (
        SELECT MAX(Id) FROM PostHistory WHERE PostId = ph.PostId AND Id < ph.Id
    )
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,24)
    GROUP BY ph.PostId
),
TopUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.AvgPostScore,
    ubs.PostCount,
    ubs.AccountAgeDays,
    tq.Id AS TopQuestionId,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.ViewCount AS TopQuestionViews,
    tq.CommentCount AS TopQuestionComments,
    ta.Id AS TopAnswerId,
    ta.QuestionTitle,
    ta.Score AS TopAnswerScore,
    ta.UpVotesCount AS TopAnswerUpVotes,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    ph.EditCount,
    ph.LastEditDate,
    ph.AvgHoursBetweenEdits,
    tua.TotalPosts,
    tua.TotalComments,
    tua.TotalVotesCast,
    tua.LastPostDate,
    tua.LastCommentDate
FROM UserBadgeStats ubs
LEFT JOIN TopQuestions tq ON tq.OwnerUserId = ubs.UserId AND tq.Rnk = 1
LEFT JOIN TopAnswers ta ON ta.OwnerUserId = ubs.UserId
LEFT JOIN QuestionAnswerStats qas ON qas.QuestionId = tq.Id
LEFT JOIN PostHistoryEdits ph ON ph.PostId = tq.Id
LEFT JOIN TopUserActivity tua ON tua.UserId = ubs.UserId
ORDER BY ubs.GoldBadges DESC, ubs.TotalBadges DESC, ubs.AvgPostScore DESC
LIMIT 100;
