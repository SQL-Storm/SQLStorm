-- {"query": "34074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 938} 
WITH QuestionAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreation,
        q.ViewCount,
        q.Score AS QuestionScore,
        q.Tags,
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(a.Id) AS AnswersCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.Tags, u.Id, u.DisplayName, u.Reputation
),
TopAnswerers AS (
    SELECT 
        a.OwnerUserId AS AnswerUserId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2 
      AND a.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
    HAVING COUNT(a.Id) > 10
),
UserBadgesSummary AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionComments AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY c.PostId
),
PostLinkCounts AS (
    SELECT 
        pl.PostId,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT 
    qa.QuestionId,
    qa.QuestionTitle,
    qa.QuestionCreation,
    qa.ViewCount,
    qa.QuestionScore,
    qa.Tags,
    qa.DisplayName AS QuestionOwner,
    qa.Reputation AS QuestionOwnerReputation,
    qa.AnswersCount,
    qa.AvgAnswerScore,
    qa.MaxAnswerScore,
    COALESCE(ub.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(ub.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS OwnerBronzeBadges,
    qc.CommentCount,
    qc.AvgCommentScore AS AvgQuestionCommentScore,
    plc.LinkedCount,
    plc.DuplicateCount,
    ta.AnswerUserId AS TopAnswererId,
    u2.DisplayName AS TopAnswererName,
    ta.AnswerCount AS TopAnswererAnswers,
    ta.AvgAnswerScore AS TopAnswererAvgScore,
    ta.MaxAnswerScore AS TopAnswererMaxScore
FROM QuestionAnswers qa
LEFT JOIN UserBadgesSummary ub ON ub.UserId = qa.UserId
LEFT JOIN QuestionComments qc ON qc.PostId = qa.QuestionId
LEFT JOIN PostLinkCounts plc ON plc.PostId = qa.QuestionId
LEFT JOIN LATERAL (
    SELECT ta.AnswerUserId, ta.AnswerCount, ta.AvgAnswerScore, ta.MaxAnswerScore
    FROM TopAnswerers ta
    INNER JOIN Posts p ON p.OwnerUserId = ta.AnswerUserId
    WHERE p.ParentId = qa.QuestionId
    ORDER BY ta.AvgAnswerScore DESC
    LIMIT 1
) ta ON true
LEFT JOIN Users u2 ON u2.Id = ta.AnswerUserId
WHERE qa.AnswersCount > 0
ORDER BY qa.QuestionScore DESC, qa.ViewCount DESC
LIMIT 100;