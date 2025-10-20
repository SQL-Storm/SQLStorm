-- {"query": "53031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1267} 

WITH Questions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.CreationDate AS QuestionDate,
        p.OwnerUserId AS AskerId,
        regexp_split_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2010-01-01'
      AND p.Score > 0
),
UnnestedTags AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.QuestionScore,
        q.ViewCount,
        q.QuestionDate,
        q.AskerId,
        unnest(q.TagArray) AS TagName
    FROM Questions q
),
TagStats AS (
    SELECT 
        ut.TagName,
        COUNT(DISTINCT ut.QuestionId) AS QuestionCount,
        AVG(ut.QuestionScore) AS AvgQuestionScore,
        SUM(ut.ViewCount) AS TotalViews,
        COUNT(DISTINCT ut.AskerId) AS UniqueAskers
    FROM UnnestedTags ut
    GROUP BY ut.TagName
    HAVING COUNT(DISTINCT ut.QuestionId) > 1000
),
Answers AS (
    SELECT 
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerDate,
        p.OwnerUserId AS AnswererId
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.Score > 0
),
AnswerStatsPerQuestion AS (
    SELECT 
        a.QuestionId,
        COUNT(a.AnswerId) AS AnswerCount,
        AVG(a.AnswerScore) AS AvgAnswerScore,
        MAX(a.AnswerScore) AS MaxAnswerScore
    FROM Answers a
    GROUP BY a.QuestionId
),
VotesOnQuestions AS (
    SELECT 
        v.PostId AS QuestionId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
TopUsersPerTag AS (
    SELECT 
        ut.TagName,
        ut.AskerId,
        COUNT(ut.QuestionId) AS QuestionsAsked,
        SUM(ut.QuestionScore) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY ut.TagName ORDER BY COUNT(ut.QuestionId) DESC, SUM(ut.QuestionScore) DESC) AS UserRank
    FROM UnnestedTags ut
    GROUP BY ut.TagName, ut.AskerId
),
BadgesPerUser AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges b
    GROUP BY b.UserId
),
CommentsOnQuestions AS (
    SELECT 
        c.PostId AS QuestionId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.Score > 0
    GROUP BY c.PostId
)
SELECT 
    ts.TagName,
    ts.QuestionCount,
    ts.AvgQuestionScore,
    ts.TotalViews,
    ts.UniqueAskers,
    COALESCE(aspq.AnswerCount, 0) AS AvgAnswerCountPerTag,
    COALESCE(aspq.AvgAnswerScore, 0) AS OverallAvgAnswerScore,
    COALESCE(aspq.MaxAnswerScore, 0) AS MaxAnswerScoreInTag,
    COALESCE(vq.Upvotes, 0) AS TotalUpvotes,
    COALESCE(vq.Downvotes, 0) AS TotalDownvotes,
    tu.AskerId AS TopUserId,
    u.DisplayName AS TopUserName,
    tu.QuestionsAsked AS TopUserQuestions,
    tu.TotalScore AS TopUserScore,
    COALESCE(bpu.BadgeCount, 0) AS TopUserBadgeCount,
    COALESCE(bpu.GoldBadges, 0) AS TopUserGoldBadges,
    COALESCE(cq.CommentCount, 0) AS TotalComments,
    COALESCE(cq.AvgCommentScore, 0) AS AvgCommentScore
FROM TagStats ts
LEFT JOIN (
    SELECT 
        ut.TagName,
        AVG(aspq.AnswerCount) AS AnswerCount,
        AVG(aspq.AvgAnswerScore) AS AvgAnswerScore,
        MAX(aspq.MaxAnswerScore) AS MaxAnswerScore
    FROM UnnestedTags ut
    JOIN AnswerStatsPerQuestion aspq ON ut.QuestionId = aspq.QuestionId
    GROUP BY ut.TagName
) aspq ON ts.TagName = aspq.TagName
LEFT JOIN (
    SELECT 
        ut.TagName,
        SUM(vq.Upvotes) AS Upvotes,
        SUM(vq.Downvotes) AS Downvotes
    FROM UnnestedTags ut
    JOIN VotesOnQuestions vq ON ut.QuestionId = vq.QuestionId
    GROUP BY ut.TagName
) vq ON ts.TagName = vq.TagName
LEFT JOIN (
    SELECT 
        ut.TagName,
        SUM(cq.CommentCount) AS CommentCount,
        AVG(cq.AvgCommentScore) AS AvgCommentScore
    FROM UnnestedTags ut
    JOIN CommentsOnQuestions cq ON ut.QuestionId = cq.QuestionId
    GROUP BY ut.TagName
) cq ON ts.TagName = cq.TagName
LEFT JOIN TopUsersPerTag tu ON ts.TagName = tu.TagName AND tu.UserRank = 1
LEFT JOIN Users u ON tu.AskerId = u.Id
LEFT JOIN BadgesPerUser bpu ON tu.AskerId = bpu.UserId
ORDER BY ts.QuestionCount DESC, ts.TotalViews DESC
LIMIT 100;
