-- {"query": "34081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 902} 

WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswersWithUsers AS (
    SELECT
        ra.AnswerId,
        ra.QuestionId,
        ra.OwnerUserId,
        ra.Score AS AnswerScore,
        ra.CreationDate AS AnswerCreationDate,
        u.DisplayName AS AnswerOwnerName,
        u.Reputation AS AnswerOwnerReputation,
        q.Title AS QuestionTitle,
        q.Tags,
        q.Score AS QuestionScore,
        q.CreationDate AS QuestionCreationDate,
        q.OwnerUserId AS QuestionOwnerUserId,
        qu.DisplayName AS QuestionOwnerName,
        COUNT(DISTINCT c.Id) AS QuestionCommentCount,
        COUNT(DISTINCT b.Id) AS QuestionBadgeCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS QuestionUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS QuestionDownVotes
    FROM RankedAnswers ra
    JOIN Posts q ON ra.QuestionId = q.Id AND q.PostTypeId = 1
    LEFT JOIN Users u ON ra.OwnerUserId = u.Id
    LEFT JOIN Users qu ON q.OwnerUserId = qu.Id
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Badges b ON b.UserId = q.OwnerUserId
    LEFT JOIN Votes v ON v.PostId = q.Id
    WHERE ra.AnswerRank = 1
    GROUP BY ra.AnswerId, ra.QuestionId, ra.OwnerUserId, ra.Score, ra.CreationDate, u.DisplayName, u.Reputation, q.Title, q.Tags, q.Score, q.CreationDate, q.OwnerUserId, qu.DisplayName
),
TagStats AS (
    SELECT
        tag.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViewCount
    FROM Tags tag
    JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE CONCAT('%<', tag.TagName, '>%')
    GROUP BY tag.TagName
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    ta.QuestionTitle,
    ta.Tags,
    ta.QuestionScore,
    ta.QuestionCreationDate,
    ta.QuestionOwnerName,
    ta.QuestionCommentCount,
    ta.QuestionBadgeCount,
    ta.QuestionUpVotes,
    ta.QuestionDownVotes,
    ta.AnswerOwnerName,
    ta.AnswerOwnerReputation,
    ta.AnswerScore,
    ta.AnswerCreationDate,
    ts.TagName,
    ts.QuestionCount AS TagQuestionCount,
    ts.AvgQuestionScore AS TagAvgQuestionScore,
    ts.TotalViewCount AS TagTotalViewCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalBadges
FROM TopAnswersWithUsers ta
LEFT JOIN TagStats ts ON ts.TagName = SUBSTRING(ta.Tags FROM 2 FOR POSITION('>' IN SUBSTRING(ta.Tags FROM 2))-1)
LEFT JOIN UserBadgeSummary ubs ON ubs.DisplayName = ta.AnswerOwnerName
WHERE ta.QuestionCreationDate BETWEEN NOW() - INTERVAL '1 year' AND NOW()
ORDER BY ta.QuestionScore DESC, ta.AnswerScore DESC
LIMIT 100;
