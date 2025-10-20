-- {"query": "53075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 681} 

WITH PopularTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagPopularity
    FROM Tags t
    ORDER BY t.Count DESC
    LIMIT 10
),
QuestionTags AS (
    SELECT 
        p.Id AS QuestionId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TaggedQuestions AS (
    SELECT 
        qt.QuestionId,
        pt.TagId
    FROM QuestionTags qt
    JOIN PopularTags pt ON qt.TagName = pt.TagName
),
UserAnswers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        q.Id AS QuestionId,
        tq.TagId
    FROM Users u
    JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    JOIN TaggedQuestions tq ON tq.QuestionId = q.Id
    WHERE u.Reputation > 1000
),
UserStats AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        COUNT(DISTINCT ua.AnswerId) AS TotalAnswers,
        AVG(ua.AnswerScore) AS AvgAnswerScore,
        COUNT(DISTINCT ua.TagId) AS UniqueTagsAnswered,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        COUNT(DISTINCT b.Id) AS GoldBadges,
        SUM(p.ViewCount) AS TotalViews
    FROM UserAnswers ua
    LEFT JOIN Votes v ON v.PostId = ua.AnswerId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON b.UserId = ua.UserId AND b.Class = 1
    LEFT JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.PostTypeId IN (1, 2)
    GROUP BY ua.UserId, ua.Reputation
    HAVING COUNT(DISTINCT ua.AnswerId) > 50
),
RankedUsers AS (
    SELECT 
        us.*,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalAnswers DESC, us.AvgAnswerScore DESC) AS Rank
    FROM UserStats us
)
SELECT 
    ru.UserId,
    ru.Reputation,
    ru.TotalAnswers,
    ru.AvgAnswerScore,
    ru.UniqueTagsAnswered,
    ru.UpvotesReceived,
    ru.GoldBadges,
    ru.TotalViews,
    (SELECT STRING_AGG(DISTINCT pt.TagName, ', ') 
     FROM UserAnswers ua 
     JOIN PopularTags pt ON pt.TagId = ua.TagId 
     WHERE ua.UserId = ru.UserId) AS TopTagsAnswered,
    (SELECT COUNT(c.Id) 
     FROM Comments c 
     WHERE c.UserId = ru.UserId) AS TotalComments
FROM RankedUsers ru
WHERE ru.Rank <= 10
ORDER BY ru.Rank;
