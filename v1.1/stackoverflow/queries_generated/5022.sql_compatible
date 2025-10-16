WITH recent_questions AS (
    SELECT 
        p.Id AS QuestionId,
        p.CreationDate,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
)
, top_questions AS (
    SELECT *
    FROM recent_questions
    WHERE rn <= 100
)
, answer_stats AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        MAX(a.Score) AS TopAnswerScore,
        AVG(NULLIF(a.Score, 0)) AS AvgNonzeroScore,
        SUM(CASE WHEN a.Score > 5 THEN 1 ELSE 0 END) AS GoodAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
)
, top_askers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS NumQuestions
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) >= 5
)
, badge_counts AS (
    SELECT 
        b.UserId, 
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    tq.QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    COALESCE(ans.AnswerCount,0) AS AnswerCount,
    ans.TopAnswerScore,
    ans.AvgNonzeroScore,
    ans.GoodAnswers,
    STRING_AGG(t.TagName, ', ') AS TagList,
    u.DisplayName AS AskerName,
    u.Reputation AS AskerReputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = tq.QuestionId
    ) AS CommentCount,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId = tq.QuestionId AND pl.LinkTypeId = 3
    ) AS DuplicateLinks,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 
            CASE 
                WHEN ph.Comment SIMILAR TO '1|101' THEN 'Duplicate'
                WHEN ph.Comment SIMILAR TO '2|102' THEN 'Off-topic'
                ELSE 'Other'
            END
        ELSE 'Open'
    END AS CloseReason,
    LEFT(p.Body, LEAST(100, LENGTH(p.Body))) || CASE WHEN LENGTH(p.Body) > 100 THEN '...' ELSE '' END AS BodyPreview
FROM top_questions tq
LEFT JOIN Posts p ON p.Id = tq.QuestionId
LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(
        substring(tq.Tags, 2, length(tq.Tags)-2), 
        '><'
    )) AS TagString
) tags ON TRUE
LEFT JOIN Tags t ON t.TagName = tags.TagString
LEFT JOIN answer_stats ans ON ans.QuestionId = tq.QuestionId
LEFT JOIN Users u ON u.Id = tq.OwnerUserId
LEFT JOIN badge_counts bc ON bc.UserId = tq.OwnerUserId
LEFT JOIN PostHistory ph ON ph.PostId = tq.QuestionId 
    AND ph.PostHistoryTypeId = 10
GROUP BY
    tq.QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    ans.AnswerCount,
    ans.TopAnswerScore,
    ans.AvgNonzeroScore,
    ans.GoodAnswers,
    u.DisplayName,
    u.Reputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    p.Id,
    p.ClosedDate,
    ph.Comment,
    p.Body
ORDER BY 
    tq.Score DESC NULLS LAST,
    tq.ViewCount DESC
LIMIT 50;