-- {"query": "53036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 799} 

WITH QuestionTags AS (
    SELECT 
        p.Id AS QuestionId, 
        p.CreationDate AS QuestionDate,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopTags AS (
    SELECT 
        Tag, 
        COUNT(DISTINCT QuestionId) AS QuestionCount,
        AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - QuestionDate)) / 86400) AS AvgQuestionAgeDays
    FROM QuestionTags
    GROUP BY Tag
    ORDER BY QuestionCount DESC
    LIMIT 20
),
AnswerTags AS (
    SELECT 
        a.Id AS AnswerId, 
        a.OwnerUserId, 
        a.Score AS AnswerScore,
        qt.Tag,
        qt.QuestionDate
    FROM Posts a
    JOIN QuestionTags qt ON qt.QuestionId = a.ParentId
    WHERE a.PostTypeId = 2
),
TopAnswerersPerTag AS (
    SELECT 
        Tag, 
        OwnerUserId, 
        COUNT(AnswerId) AS AnswerCount,
        SUM(AnswerScore) AS TotalAnswerScore,
        AVG(AnswerScore) AS AvgAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY Tag ORDER BY COUNT(AnswerId) DESC, SUM(AnswerScore) DESC) AS rn
    FROM AnswerTags
    GROUP BY Tag, OwnerUserId
),
TagBadges AS (
    SELECT 
        b.UserId,
        t.TagName AS Tag,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    JOIN Tags t ON b.Name = t.TagName AND b.TagBased = TRUE
    GROUP BY b.UserId, t.TagName
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT v.Id) AS VotesCast,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditsMade
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    tt.Tag, 
    tt.QuestionCount,
    tt.AvgQuestionAgeDays,
    ua.DisplayName AS TopAnswerer,
    ua.Reputation,
    tap.AnswerCount,
    tap.TotalAnswerScore,
    tap.AvgAnswerScore,
    COALESCE(tb.BadgeCount, 0) AS TotalTagBadges,
    COALESCE(tb.GoldBadges, 0) AS GoldTagBadges,
    COALESCE(tb.SilverBadges, 0) AS SilverTagBadges,
    COALESCE(tb.BronzeBadges, 0) AS BronzeTagBadges,
    ua.VotesCast,
    ua.CommentsMade,
    ua.EditsMade
FROM TopTags tt
JOIN TopAnswerersPerTag tap ON tap.Tag = tt.Tag AND tap.rn = 1
JOIN UserActivity ua ON ua.UserId = tap.OwnerUserId
LEFT JOIN TagBadges tb ON tb.UserId = tap.OwnerUserId AND tb.Tag = tt.Tag
ORDER BY tt.QuestionCount DESC, tap.TotalAnswerScore DESC;
