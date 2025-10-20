-- {"query": "46064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 146816, "output_tokens": 117914} 
WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01' 
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionQualityMetrics AS (
    SELECT 
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.CommentCount,
        q.CreationDate AS QuestionCreationDate,
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2), '><') AS TagArray,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        COUNT(DISTINCT pl.Id) AS LinkedPostCount,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS Favorites,
        AVG(ans.Score) AS AvgAnswerScore,
        MAX(ans.Score) AS MaxAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Posts ans ON q.Id = ans.ParentId AND ans.PostTypeId = 2
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId
    LEFT JOIN Votes v ON q.Id = v.PostId
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= TIMESTAMP '2019-01-01'
        AND q.Score >= 5
        AND q.AnswerCount > 0
    GROUP BY q.Id, q.OwnerUserId, q.Title, q.Score, q.ViewCount, q.AnswerCount, 
             q.FavoriteCount, q.CommentCount, q.CreationDate, q.Tags, a.Id, a.Score
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        AVG(p.Score) AS AvgTagScore,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
        SUM(p.ViewCount) AS TotalTagViews
    FROM Tags t
    INNER JOIN Posts p ON SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
        AND t.Count > 100
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 50
),
TopContributorsByTag AS (
    SELECT 
        tp.TagName,
        uem.UserId,
        uem.DisplayName,
        uem.Reputation,
        uem.TotalPosts,
        tp.AvgTagScore,
        ROW_NUMBER() OVER (PARTITION BY tp.TagName ORDER BY uem.Reputation DESC, uem.TotalPosts DESC) AS RankInTag
    FROM TagPopularity tp
    CROSS JOIN UserEngagementMetrics uem
    INNER JOIN Posts p ON uem.UserId = p.OwnerUserId
    WHERE SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) LIKE '%' || tp.TagName || '%'
        AND p.PostTypeId = 1
),
AnswerResponseTime AS (
    SELECT 
        qq.QuestionId,
        qq.QuestionCreationDate,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreationDate,
        EXTRACT(EPOCH FROM (a.CreationDate - qq.QuestionCreationDate))/3600 AS HoursToAnswer,
        a.Score AS AnswerScore,
        CASE WHEN qq.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted
    FROM QuestionQualityMetrics qq
    INNER JOIN Posts a ON qq.QuestionId = a.ParentId
    WHERE a.PostTypeId = 2
)
SELECT 
    tp.TagName,
    tp.TagCount,
    tp.AvgTagScore,
    tp.UniqueContributors,
    tp.QuestionsWithAcceptedAnswer,
    ROUND(tp.QuestionsWithAcceptedAnswer::NUMERIC / NULLIF(tp.TagCount, 0) * 100, 2) AS AcceptanceRate,
    tc.DisplayName AS TopContributor,
    tc.Reputation AS TopContributorReputation,
    tc.TotalPosts AS TopContributorPosts,
    COUNT(DISTINCT qq.QuestionId) AS RecentQuestions,
    AVG(qq.ViewCount) AS AvgViewsPerQuestion,
    AVG(qq.AnswerCount) AS AvgAnswersPerQuestion,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY art.HoursToAnswer) AS MedianResponseTimeHours,
    AVG(CASE WHEN art.IsAccepted = 1 THEN art.HoursToAnswer END) AS AvgAcceptedAnswerTimeHours,
    COUNT(DISTINCT uem.UserId) AS ActiveUsers,
    SUM(uem.BadgeCount) AS TotalBadgesInTag,
    ROUND(AVG(uem.AvgPostScore), 2) AS AvgUserPostScore
FROM TagPopularity tp
LEFT JOIN TopContributorsByTag tc ON tp.TagName = tc.TagName AND tc.RankInTag = 1
LEFT JOIN QuestionQualityMetrics qq ON ARRAY_TO_STRING(qq.TagArray, ',') LIKE '%' || tp.TagName || '%'
LEFT JOIN AnswerResponseTime art ON qq.QuestionId = art.QuestionId
LEFT JOIN UserEngagementMetrics uem ON qq.OwnerUserId = uem.UserId
GROUP BY tp.TagName, tp.TagCount, tp.AvgTagScore, tp.UniqueContributors, 
         tp.QuestionsWithAcceptedAnswer, tc.DisplayName, tc.Reputation, tc.TotalPosts
HAVING COUNT(DISTINCT qq.QuestionId) > 10
ORDER BY tp.TagCount DESC, tp.AvgTagScore DESC
LIMIT 100;