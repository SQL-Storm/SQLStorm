-- {"query": "53012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 700} 
WITH TagQuestions AS (
    SELECT 
        t.tag, 
        p.Id AS QuestionId, 
        p.OwnerUserId AS AskerId, 
        p.Score AS QuestionScore, 
        p.ViewCount, 
        p.CreationDate
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(tag)
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        a.ParentId, 
        a.OwnerUserId, 
        a.Score, 
        a.CommentCount, 
        LENGTH(a.Body) AS AnswerLength
    FROM Posts a
    WHERE a.PostTypeId = 2
),
VoteStats AS (
    SELECT 
        v.PostId, 
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes, 
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Votes v
    GROUP BY v.PostId
),
TopAnswerersPerTag AS (
    SELECT 
        tq.tag, 
        ans.OwnerUserId, 
        COUNT(*) AS AnswersCount, 
        SUM(ans.Score) AS TotalAnswerScore, 
        AVG(ans.AnswerLength) AS AvgAnswerLength, 
        AVG(tq.QuestionScore) AS AvgQuestionScore, 
        SUM(tq.ViewCount) AS TotalViews,
        ROW_NUMBER() OVER (PARTITION BY tq.tag ORDER BY COUNT(*) DESC, SUM(ans.Score) DESC) AS rn
    FROM TagQuestions tq
    JOIN AnswerStats ans ON ans.ParentId = tq.QuestionId
    GROUP BY tq.tag, ans.OwnerUserId
),
TagBadgeCounts AS (
    SELECT 
        b.UserId, 
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
)
SELECT 
    tap.tag, 
    u.DisplayName, 
    u.Reputation, 
    tap.AnswersCount, 
    tap.TotalAnswerScore, 
    tap.AvgAnswerLength, 
    tap.AvgQuestionScore, 
    tap.TotalViews, 
    COALESCE(tbc.GoldBadges, 0) AS GoldBadges, 
    COALESCE(tbc.SilverBadges, 0) AS SilverBadges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId IN (SELECT QuestionId FROM TagQuestions tq2 WHERE tq2.tag = tap.tag) AND ph.PostHistoryTypeId IN (4,5,6)) AS TotalEditsInTag
FROM TopAnswerersPerTag tap
JOIN Users u ON u.Id = tap.OwnerUserId
LEFT JOIN TagBadgeCounts tbc ON tbc.UserId = tap.OwnerUserId
LEFT JOIN VoteStats vs ON vs.PostId = (SELECT MAX(QuestionId) FROM TagQuestions tq3 WHERE tq3.tag = tap.tag)
WHERE tap.rn = 1 AND tap.AnswersCount > 100
ORDER BY tap.AnswersCount DESC, tap.TotalAnswerScore DESC
LIMIT 100;