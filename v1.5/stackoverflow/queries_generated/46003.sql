-- {"query": "46003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 6882, "output_tokens": 4748} 

WITH TopQuestionUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgQuestionScore,
        SUM(p.ViewCount) as TotalViews
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
        AND p.Score > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 5
),
AnswerEngagement AS (
    SELECT 
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwnerId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.CreationDate) as LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON q.Id = c.PostId
    LEFT JOIN Votes v ON q.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= '2019-01-01'
    GROUP BY q.Id, q.OwnerUserId
),
TagPerformance AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) as PostCount,
        AVG(p.Score) as AvgScore,
        AVG(p.ViewCount) as AvgViews,
        COUNT(DISTINCT b.UserId) as ExpertCount
    FROM Tags t
    INNER JOIN Posts p ON POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    LEFT JOIN Badges b ON b.Name = t.TagName AND b.TagBased = 1
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2018-01-01'
    GROUP BY t.Id, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 100
),
UserEditActivity AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) as EditedPosts,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) as BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) as TitleEdits,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))/86400) as AvgDaysToEdit
    FROM PostHistory ph
    INNER JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
        AND ph.UserId IS NOT NULL
        AND ph.CreationDate >= '2020-01-01'
    GROUP BY ph.UserId
)
SELECT 
    tqu.DisplayName,
    tqu.Reputation,
    tqu.QuestionCount,
    ROUND(tqu.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    tqu.TotalViews,
    ROUND(AVG(ae.AnswerCount)::numeric, 2) as AvgAnswersPerQuestion,
    ROUND(AVG(ae.CommentCount)::numeric, 2) as AvgCommentsPerQuestion,
    ROUND(AVG(ae.VoteCount)::numeric, 2) as AvgVotesPerQuestion,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COALESCE(uea.EditedPosts, 0) as EditedPosts,
    COALESCE(uea.BodyEdits, 0) as BodyEdits,
    STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagName) FILTER (WHERE tp.PostCount IS NOT NULL) as TopTags,
    ROUND(AVG(tp.AvgScore)::numeric, 2) as AvgTagScore,
    ROUND(AVG(EXTRACT(EPOCH FROM (ae.LastAnswerDate - p.CreationDate))/3600)::numeric, 2) as AvgHoursToLastAnswer
FROM TopQuestionUsers tqu
INNER JOIN Posts p ON tqu.Id = p.OwnerUserId AND p.PostTypeId = 1
INNER JOIN AnswerEngagement ae ON p.Id = ae.QuestionId
LEFT JOIN Badges b ON tqu.Id = b.UserId
LEFT JOIN UserEditActivity uea ON tqu.Id = uea.UserId
LEFT JOIN TagPerformance tp ON POSITION('<' || tp.TagName || '>' IN p.Tags) > 0
WHERE ae.AnswerCount > 0
GROUP BY 
    tqu.Id,
    tqu.DisplayName,
    tqu.Reputation,
    tqu.QuestionCount,
    tqu.AvgQuestionScore,
    tqu.TotalViews,
    uea.EditedPosts,
    uea.BodyEdits
HAVING COUNT(DISTINCT p.Id) >= 3
    AND AVG(ae.AnswerCount) >= 2
ORDER BY 
    tqu.Reputation DESC,
    AVG(ae.VoteCount) DESC
LIMIT 100;
