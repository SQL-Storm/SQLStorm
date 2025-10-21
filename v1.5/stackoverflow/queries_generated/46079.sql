-- {"query": "46079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 181226, "output_tokens": 144809} 

WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
        AND p.Score >= 5
    GROUP BY p.OwnerUserId, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as QuestionId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.Score) as BestAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) as UniqueAnswerers,
        MIN(a.CreationDate) as FirstAnswerTime,
        MAX(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.CreationDate END) as AcceptedAnswerTime
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
    GROUP BY a.ParentId
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpvotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownvotesGiven,
        COUNT(DISTINCT c.Id) as CommentsPosted,
        COUNT(DISTINCT b.Id) as BadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        COUNT(DISTINCT p.OwnerUserId) as UniqueContributors,
        AVG(p.Score) as AvgQuestionScore,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END)::FLOAT / 
            NULLIF(COUNT(DISTINCT p.Id), 0) as AcceptanceRate
    FROM Tags t
    INNER JOIN Posts p ON string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') && ARRAY[t.TagName]
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) >= 100
)
SELECT 
    tqa.DisplayName,
    tqa.QuestionCount,
    ROUND(tqa.AvgScore::numeric, 2) as AvgQuestionScore,
    tqa.TotalViews,
    ROUND(AVG(am.AnswerCount)::numeric, 2) as AvgAnswersPerQuestion,
    ROUND(AVG(am.AvgAnswerScore)::numeric, 2) as AvgAnswerScoreReceived,
    ROUND(AVG(EXTRACT(EPOCH FROM (am.FirstAnswerTime - p.CreationDate))/3600)::numeric, 2) as AvgHoursToFirstAnswer,
    ue.CommentsPosted,
    ue.UpvotesGiven,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    COUNT(DISTINCT pl.RelatedPostId) as QuestionsLinked,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) as DuplicatesMarked,
    STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagCount DESC) FILTER (WHERE tp.TagCount IS NOT NULL) as TopTags,
    ROUND(AVG(tp.AcceptanceRate)::numeric, 3) as AvgTagAcceptanceRate
FROM TopQuestionAuthors tqa
INNER JOIN Posts p ON tqa.OwnerUserId = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN AnswerMetrics am ON p.Id = am.QuestionId
LEFT JOIN UserEngagement ue ON tqa.OwnerUserId = ue.UserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN TagPopularity tp ON string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') && ARRAY[tp.TagName]
WHERE p.CreationDate >= TIMESTAMP '2020-01-01'
GROUP BY 
    tqa.DisplayName, 
    tqa.QuestionCount, 
    tqa.AvgScore, 
    tqa.TotalViews,
    ue.CommentsPosted,
    ue.UpvotesGiven,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges
HAVING COUNT(DISTINCT p.Id) >= 10
ORDER BY 
    tqa.TotalViews DESC,
    tqa.AvgScore DESC
LIMIT 100;
