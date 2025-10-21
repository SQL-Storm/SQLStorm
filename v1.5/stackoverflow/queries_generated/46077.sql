-- {"query": "46077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1804}

WITH RECURSIVE UserInfluence AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as TotalUpvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as TotalDownvotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) >= 5
),
QuestionAnswerNetwork AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswererId,
        q.OwnerUserId as QuestionerId,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.CreationDate >= NOW() - INTERVAL '18 months'
        AND q.Score >= 5
),
TagPerformance AS (
    SELECT 
        tag_element as TagName,
        COUNT(DISTINCT qan.QuestionId) as QuestionCount,
        AVG(qan.QuestionScore) as AvgQuestionScore,
        AVG(qan.AnswerCount) as AvgAnswerCount,
        AVG(qan.ViewCount) as AvgViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qan.QuestionScore) as MedianScore,
        COUNT(DISTINCT qan.AnswererId) as UniqueAnswerers
    FROM QuestionAnswerNetwork qan
    CROSS JOIN LATERAL unnest(string_to_array(substring(qan.Tags, 2, length(qan.Tags)-2), '><')) as tag_element
    GROUP BY tag_element
    HAVING COUNT(DISTINCT qan.QuestionId) >= 10
),
ExpertIdentification AS (
    SELECT 
        ui.Id as UserId,
        ui.DisplayName,
        ui.Reputation,
        tag_element as ExpertTag,
        COUNT(DISTINCT qan.AnswerId) as AnswersInTag,
        AVG(qan.AnswerScore) as AvgAnswerScore,
        SUM(qan.IsAccepted) as AcceptedAnswers,
        DENSE_RANK() OVER (PARTITION BY tag_element ORDER BY COUNT(DISTINCT qan.AnswerId) DESC, AVG(qan.AnswerScore) DESC) as ExpertRank
    FROM UserInfluence ui
    INNER JOIN QuestionAnswerNetwork qan ON ui.Id = qan.AnswererId
    CROSS JOIN LATERAL unnest(string_to_array(substring(qan.Tags, 2, length(qan.Tags)-2), '><')) as tag_element
    WHERE qan.AnswerRank <= 3
    GROUP BY ui.Id, ui.DisplayName, ui.Reputation, tag_element
    HAVING COUNT(DISTINCT qan.AnswerId) >= 3
),
CommentEngagement AS (
    SELECT 
        c.UserId,
        COUNT(DISTINCT c.PostId) as CommentedPosts,
        AVG(c.Score) as AvgCommentScore,
        COUNT(DISTINCT DATE_TRUNC('day', c.CreationDate)) as ActiveDays
    FROM Comments c
    WHERE c.CreationDate >= NOW() - INTERVAL '1 year'
        AND c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    ei.ExpertTag,
    ei.UserId,
    ei.DisplayName,
    ei.Reputation,
    ei.AnswersInTag,
    ei.AvgAnswerScore,
    ei.AcceptedAnswers,
    tp.QuestionCount as TagQuestionCount,
    tp.AvgQuestionScore as TagAvgScore,
    tp.UniqueAnswerers as TagTotalExperts,
    ce.CommentedPosts,
    ce.AvgCommentScore,
    COALESCE(badge_counts.GoldBadges, 0) as GoldBadges,
    COALESCE(badge_counts.SilverBadges, 0) as SilverBadges,
    COALESCE(badge_counts.BronzeBadges, 0) as BronzeBadges,
    (ei.AvgAnswerScore * 0.3 + 
     ei.AcceptedAnswers * 0.25 + 
     (ei.AnswersInTag::float / NULLIF(tp.QuestionCount, 0)) * 100 * 0.2 +
     COALESCE(ce.AvgCommentScore, 0) * 0.15 +
     (COALESCE(badge_counts.GoldBadges, 0) * 3 + COALESCE(badge_counts.SilverBadges, 0) * 2 + COALESCE(badge_counts.BronzeBadges, 0)) * 0.1
    ) as InfluenceScore
FROM ExpertIdentification ei
INNER JOIN TagPerformance tp ON ei.ExpertTag = tp.TagName
LEFT JOIN CommentEngagement ce ON ei.UserId = ce.UserId
LEFT JOIN (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) as BronzeBadges
    FROM Badges
    GROUP BY UserId
) badge_counts ON ei.UserId = badge_counts.UserId
WHERE ei.ExpertRank <= 10
    AND tp.QuestionCount >= 50
ORDER BY tp.QuestionCount DESC, ei.ExpertRank ASC, InfluenceScore DESC
LIMIT 500;
