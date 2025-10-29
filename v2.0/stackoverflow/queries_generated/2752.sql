-- {"query": "2752.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1599} 
WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE NOT t.IsRequired = 1

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON ARRAY_LENGTH(r.TagPath, 1) < 3 AND t.Id != r.Id
    WHERE NOT t.IsModeratorOnly = 1
),

UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(b.Id) AS BadgeCount,
        AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(v.BountyAmount) AS TotalBountyGiven,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        LEAD(u.Reputation) OVER (ORDER BY u.Reputation DESC) AS NextReputation,
        LAG(u.Reputation) OVER (ORDER BY u.Reputation DESC) AS PrevReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 8
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

PostCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
),

UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(COALESCE(c.Score,0)) AS TotalCommentScore
    FROM Comments c
    GROUP BY c.UserId
),

-- Correlated subquery calculates the time difference between question post creation and accepted answer creation
PostAnswerDelays AS (
    SELECT DISTINCT
        q.Id AS QuestionId,
        q.CreationDate AS QuestionCreationDate,
        a.CreationDate AS AcceptedAnswerCreationDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAcceptedAnswer
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),

HighImpactPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score >= 10
),

FinalUserSummary AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.QuestionsAsked,
        ups.AnswersGiven,
        ups.BadgeCount,
        ups.AvgPostScore,
        ucs.CommentCount,
        ucs.AvgCommentLength,
        ucs.TotalCommentScore,
        COALESCE(SUM(phr.PostId IS NOT NULL)::INT,0) AS ClosedQuestionsCount,
        COALESCE(SUM(hp.Id IS NOT NULL)::INT, 0) AS HighImpactQuestionCount,
        MAX(pad.HoursToAcceptedAnswer) FILTER (WHERE pad.HoursToAcceptedAnswer IS NOT NULL) AS MaxAnswerDelayHours,
        ups.ReputationRank,
        ups.NextReputation,
        ups.PrevReputation
    FROM UserPostStats ups
    LEFT JOIN UserCommentStats ucs ON ucs.UserId = ups.UserId
    LEFT JOIN PostCloseReasons phr ON phr.PostId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ups.UserId AND p.PostTypeId = 1
    )
    LEFT JOIN HighImpactPosts hp ON hp.OwnerUserId = ups.UserId
    LEFT JOIN PostAnswerDelays pad ON pad.QuestionId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ups.UserId AND p.PostTypeId = 1
    )
    GROUP BY ups.UserId, ups.DisplayName, ups.Reputation, ups.QuestionsAsked, ups.AnswersGiven,
        ups.BadgeCount, ups.AvgPostScore, ucs.CommentCount, ucs.AvgCommentLength, ucs.TotalCommentScore,
        ups.ReputationRank, ups.NextReputation, ups.PrevReputation
)

SELECT
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.QuestionsAsked,
    fus.AnswersGiven,
    fus.BadgeCount,
    ROUND(fus.AvgPostScore,2) AS AvgPostScore,
    fus.CommentCount,
    ROUND(fus.AvgCommentLength,2) AS AvgCommentLength,
    fus.TotalCommentScore,
    fus.ClosedQuestionsCount,
    fus.HighImpactQuestionCount,
    COALESCE(ROUND(fus.MaxAnswerDelayHours,2), NULL) AS MaxAnswerDelayHours,
    fus.ReputationRank,
    CASE
        WHEN fus.NextReputation IS NULL THEN NULL
        ELSE fus.NextReputation - fus.Reputation
    END AS ReputationGapToNext,
    CASE
        WHEN fus.PrevReputation IS NULL THEN NULL
        ELSE fus.Reputation - fus.PrevReputation
    END AS ReputationGapToPrev,
    
    -- Complex string expressions: concatenated tag paths of popular tags (with count > 1000)
    (SELECT STRING_AGG(DISTINCT th.TagName, ' > ' ORDER BY th.TagName)
     FROM RecursiveTagHierarchy th
     WHERE th.Count > 1000
       AND th.Id IN (SELECT Id FROM Tags WHERE TagName IS NOT NULL)
    ) AS PopularTagPathConcat,

    -- Conditional aggregation with NULL logic and complex predicate on user location and website URL
    COUNT(DISTINCT CASE
        WHEN LOWER(u.Location) LIKE '%united states%'
             OR (u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE 'http%') THEN p.Id
        ELSE NULL END
    ) AS PostsFromUSOrWithSite

FROM FinalUserSummary fus
LEFT JOIN Users u ON u.Id = fus.UserId
LEFT JOIN Posts p ON p.OwnerUserId = fus.UserId
GROUP BY fus.UserId, fus.DisplayName, fus.Reputation, fus.QuestionsAsked, fus.AnswersGiven, fus.BadgeCount,
         fus.AvgPostScore, fus.CommentCount, fus.AvgCommentLength, fus.TotalCommentScore,
         fus.ClosedQuestionsCount, fus.HighImpactQuestionCount, fus.MaxAnswerDelayHours,
         fus.ReputationRank, fus.NextReputation, fus.PrevReputation, u.Location, u.WebsiteUrl

ORDER BY fus.Reputation DESC
LIMIT 50;