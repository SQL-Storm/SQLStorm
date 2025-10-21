-- {"query": "34006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1100} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    WHERE u.Reputation > 10000
),
UserBadgeStats AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges
    FROM Badges b
    WHERE b.UserId IN (SELECT Id FROM TopUsers)
    GROUP BY b.UserId
),
UserPostStats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
           SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
           MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT Id FROM TopUsers)
    GROUP BY p.OwnerUserId
),
UserRecentActivity AS (
    SELECT ph.UserId,
           COUNT(DISTINCT ph.PostId) AS EditedPostsCount,
           COUNT(*) AS TotalEdits,
           MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.UserId IN (SELECT Id FROM TopUsers)
      AND ph.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY ph.UserId
),
QuestionAnswerLinks AS (
    SELECT q.Id AS QuestionId, q.Title, q.CreationDate AS QuestionCreation,
           a.Id AS AnswerId, a.OwnerUserId AS AnswerUserId, a.Score AS AnswerScore, a.CreationDate AS AnswerCreation
    FROM Posts q
    JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
AnswerVoteStats AS (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.PostId IN (SELECT AnswerId FROM QuestionAnswerLinks)
    GROUP BY v.PostId
),
HotQuestions AS (
    SELECT q.QuestionId, q.Title, q.QuestionCreation,
           COUNT(DISTINCT a.AnswerId) AS NumAnswers,
           COALESCE(SUM(av.UpVotes) - SUM(av.DownVotes), 0) AS NetVotes,
           AVG(DATE_PART('day', a.AnswerCreation - q.QuestionCreation)) AS AvgAnswerDelay
    FROM QuestionAnswerLinks q
    LEFT JOIN AnswerVoteStats av ON av.PostId = q.AnswerId
    GROUP BY q.QuestionId, q.Title, q.QuestionCreation
    HAVING COUNT(DISTINCT q.AnswerId) >= 5
       AND COALESCE(SUM(av.UpVotes) - SUM(av.DownVotes), 0) >= 20
)
SELECT 
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalBadges,
    ups.QuestionCount,
    ups.AnswerCount,
    ROUND(ups.AvgPostScore::numeric, 2) AS AvgPostScore,
    ups.TotalQuestionViews,
    ups.LastPostDate,
    ura.EditedPostsCount,
    ura.TotalEdits,
    ura.LastEditDate,
    hq.QuestionId,
    hq.Title AS HotQuestionTitle,
    hq.QuestionCreation,
    hq.NumAnswers,
    hq.NetVotes,
    ROUND(hq.AvgAnswerDelay::numeric, 2) AS AvgAnswerDelayDays
FROM TopUsers tu
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = tu.Id
LEFT JOIN UserPostStats ups ON ups.UserId = tu.Id
LEFT JOIN UserRecentActivity ura ON ura.UserId = tu.Id
LEFT JOIN (
    SELECT DISTINCT ON (p.OwnerUserId) p.OwnerUserId, hq.*
    FROM HotQuestions hq
    JOIN Posts p ON p.Id = hq.QuestionId
    WHERE p.OwnerUserId IS NOT NULL
    ORDER BY p.OwnerUserId, hq.NetVotes DESC, hq.NumAnswers DESC
) hq ON hq.OwnerUserId = tu.Id
WHERE tu.RepRank <= 100
ORDER BY tu.Reputation DESC, ubs.GoldBadges DESC, ups.QuestionCount DESC
LIMIT 100;
