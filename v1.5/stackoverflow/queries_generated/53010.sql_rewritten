-- {"query": "53010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1074} 
WITH Questions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score AS QuestionScore,
        p.CreationDate AS QuestionDate,
        p.OwnerUserId AS AskerId,
        u.DisplayName AS AskerName,
        u.Reputation AS AskerReputation,
        string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') AS TagArray
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2020-01-01'
),
UnnestedQuestions AS (
    SELECT 
        q.*,
        unnest(q.TagArray) AS TagName
    FROM Questions q
),
PopularTags AS (
    SELECT 
        TagName,
        COUNT(DISTINCT QuestionId) AS QuestionCount,
        AVG(QuestionScore) AS AvgScore
    FROM UnnestedQuestions
    GROUP BY TagName
    HAVING COUNT(DISTINCT QuestionId) > 1000
    ORDER BY QuestionCount DESC
    LIMIT 50
),
Answers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        a.OwnerUserId AS AnswererId,
        u.DisplayName AS AnswererName,
        u.Reputation AS AnswererReputation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS Rank
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= '2020-01-01'
),
TopAnswersPerQuestion AS (
    SELECT 
        QuestionId,
        AnswerId,
        AnswerScore,
        AnswerDate,
        AnswererId,
        AnswererName,
        AnswererReputation
    FROM Answers
    WHERE Rank = 1
),
VotesOnQuestions AS (
    SELECT 
        v.PostId AS QuestionId,
        COUNT(*) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
CommentsOnQuestions AS (
    SELECT 
        c.PostId AS QuestionId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
PostHistoryEdits AS (
    SELECT 
        ph.PostId AS QuestionId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY ph.PostId
),
BadgesForAskers AS (
    SELECT 
        b.UserId AS AskerId,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges b
    GROUP BY b.UserId
),
LinkedPosts AS (
    SELECT 
        pl.PostId AS QuestionId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
    GROUP BY pl.PostId
)
SELECT 
    pt.TagName,
    pt.QuestionCount,
    pt.AvgScore,
    uq.QuestionId,
    uq.Title,
    uq.QuestionScore,
    uq.QuestionDate,
    uq.AskerName,
    uq.AskerReputation,
    ta.AnswerId,
    ta.AnswerScore,
    ta.AnswerDate,
    ta.AnswererName,
    ta.AnswererReputation,
    vq.VoteCount,
    vq.Upvotes,
    vq.Downvotes,
    cq.CommentCount,
    cq.AvgCommentScore,
    phe.EditCount,
    phe.LastEditDate,
    ba.BadgeCount AS AskerBadgeCount,
    ba.GoldBadges AS AskerGoldBadges,
    lp.LinkedCount
FROM PopularTags pt
JOIN UnnestedQuestions uq ON pt.TagName = uq.TagName
LEFT JOIN TopAnswersPerQuestion ta ON uq.QuestionId = ta.QuestionId
LEFT JOIN VotesOnQuestions vq ON uq.QuestionId = vq.QuestionId
LEFT JOIN CommentsOnQuestions cq ON uq.QuestionId = cq.QuestionId
LEFT JOIN PostHistoryEdits phe ON uq.QuestionId = phe.QuestionId
LEFT JOIN BadgesForAskers ba ON uq.AskerId = ba.AskerId
LEFT JOIN LinkedPosts lp ON uq.QuestionId = lp.QuestionId
WHERE uq.QuestionScore > 10
ORDER BY pt.QuestionCount DESC, uq.QuestionScore DESC
LIMIT 10000;