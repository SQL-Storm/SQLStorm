WITH TagCounts AS (
    SELECT 
        p.Id              AS QuestionId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.Reputation      AS AskerReputation,
        p.OwnerUserId,
        splitTags.tag AS Tag
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    JOIN LATERAL (
        SELECT regexp_replace(regexp_replace(p.Tags, '><', '</x><x>'), '^<|>$', '', 'g') AS inner_tags
    ) AS replaced ON true
    JOIN LATERAL (
        SELECT unnest(string_to_array(replaced.inner_tags, '</x><x>')) AS tag_element
    ) AS elems ON true
    JOIN LATERAL (
        SELECT regexp_replace(elems.tag_element, '^<|>$', '', 'g') AS tag
    ) AS splitTags ON true
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (cast('2024-10-01' as date) + INTERVAL '-2 year') + (CAST('2024-10-01 12:34:56' AS timestamp) - CAST('2024-10-01' AS date))
),
AnswerStats AS (
    SELECT 
        q.Id                           AS QuestionId,
        COUNT(a.Id)                    AS TotalAnswers,
        AVG(a.Score)                   AS AvgAnswerScore,
        MAX(a.Score)                   AS MaxAnswerScore,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600) AS AvgAnswerDelayHours
    FROM Posts q
    JOIN Posts a
      ON a.ParentId = q.Id
     AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
CommentStats AS (
    SELECT 
        p.Id            AS QuestionId,
        COUNT(c.Id)     AS TotalComments,
        AVG(c.Score)    AS AvgCommentScore
    FROM Posts p
    LEFT JOIN Comments c
      ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id
),
BadgeStats AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
RankedTags AS (
    SELECT 
        tc.Tag,
        COUNT(DISTINCT tc.QuestionId)        AS QuestionCount,
        AVG(tc.Score)                        AS AvgQuestionScore,
        AVG(tc.ViewCount)                    AS AvgQuestionViews,
        AVG(tc.AskerReputation)              AS AvgAskerReputation,
        SUM(COALESCE(a.TotalAnswers,  0))    AS AnswersSum,
        AVG(a.AvgAnswerScore)                AS AvgAnswerScore,
        SUM(COALESCE(cs.TotalComments, 0))   AS CommentsSum,
        SUM(COALESCE(bs.GoldBadges, 0))      AS TagGoldBadges,
        SUM(COALESCE(bs.SilverBadges, 0))    AS TagSilverBadges,
        SUM(COALESCE(bs.BronzeBadges, 0))    AS TagBronzeBadges,
        RANK() OVER (ORDER BY COUNT(DISTINCT tc.QuestionId) DESC) AS TagRank
    FROM TagCounts tc
    LEFT JOIN AnswerStats a
      ON tc.QuestionId = a.QuestionId
    LEFT JOIN CommentStats cs
      ON tc.QuestionId = cs.QuestionId
    LEFT JOIN BadgeStats bs
      ON tc.OwnerUserId = bs.UserId
    GROUP BY tc.Tag
)
SELECT 
    rt.Tag,
    rt.QuestionCount,
    rt.AvgQuestionScore,
    rt.AvgQuestionViews,
    rt.AvgAskerReputation,
    rt.AnswersSum,
    rt.AvgAnswerScore,
    rt.CommentsSum,
    rt.TagGoldBadges,
    rt.TagSilverBadges,
    rt.TagBronzeBadges
FROM RankedTags rt
WHERE rt.TagRank <= 20
ORDER BY rt.TagRank, rt.CommentsSum DESC;