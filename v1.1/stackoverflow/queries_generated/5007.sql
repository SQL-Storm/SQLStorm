-- {"query": "5007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 891} 
WITH RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate > NOW() - INTERVAL '90 days'
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswers,
        MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(*) AS TotalComments,
        MAX(c.Score) AS MaxCommentScore,
        SUM(CASE WHEN c.Score > 5 THEN 1 ELSE 0 END) AS HighScoreComments
    FROM Comments c
    GROUP BY c.PostId
),
PopularTags AS (
    SELECT
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagUsage
    FROM RecentQuestions q
    GROUP BY Tag
    HAVING COUNT(*) > 5
),
OwnerBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score AS QuestionScore,
    rq.OwnerUserId,
    COALESCE(rq.OwnerDisplayName, '[anonymous]') AS OwnerDisplayName,
    ob.GoldBadges,
    ob.SilverBadges,
    ob.BronzeBadges,
    a.TotalAnswers,
    a.AvgAnswerScore,
    a.PositiveAnswers,
    a.LastAnswerDate,
    cs.TotalComments,
    cs.MaxCommentScore,
    cs.HighScoreComments,
    STRING_AGG(DISTINCT pt.Tag, ', ' ORDER BY pt.Tag) AS PopularTagsUsed,
    CASE 
        WHEN rq.ViewCount IS NULL OR a.TotalAnswers IS NULL THEN NULL
        ELSE ROUND(CASE WHEN a.TotalAnswers = 0 THEN NULL ELSE rq.ViewCount::numeric / a.TotalAnswers END,2)
    END AS ViewAnswerRatio,
    CASE 
        WHEN rq.Score > 0 AND a.AvgAnswerScore > 0 THEN 'Hot'
        WHEN rq.Score < 0 THEN 'Low Quality'
        ELSE 'Average'
    END AS QualityCategory
FROM RecentQuestions rq
LEFT JOIN AnswerStats a ON rq.QuestionId = a.QuestionId
LEFT JOIN CommentStats cs ON rq.QuestionId = cs.PostId
LEFT JOIN OwnerBadges ob ON rq.OwnerUserId = ob.UserId
LEFT JOIN LATERAL (
    SELECT pt.Tag
    FROM PopularTags pt
    WHERE ('<' || pt.Tag || '>') = ANY(string_to_array(rq.Tags, '><'))
) pt ON true
WHERE rq.RowNum <= 100
GROUP BY
    rq.QuestionId, rq.Title, rq.CreationDate, rq.ViewCount, rq.Score, rq.OwnerUserId, rq.OwnerDisplayName,
    ob.GoldBadges, ob.SilverBadges, ob.BronzeBadges,
    a.TotalAnswers, a.AvgAnswerScore, a.PositiveAnswers, a.LastAnswerDate,
    cs.TotalComments, cs.MaxCommentScore, cs.HighScoreComments
ORDER BY
    CASE WHEN a.TotalAnswers IS NULL THEN 1 ELSE 0 END, -- Questions with no answers last
    rq.ViewCount DESC,
    rq.CreationDate DESC;