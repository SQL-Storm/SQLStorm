WITH RecentActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           COUNT(DISTINCT p.Id) AS QuestionCount,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           AVG(p.Score) AS AvgQuestionScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) >= 5
),
TopAnswerers AS (
    SELECT p.OwnerUserId, 
           COUNT(*) AS AnswerCount,
           SUM(CASE WHEN p.Id = parent.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedCount,
           AVG(p.Score) AS AvgAnswerScore,
           MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    INNER JOIN Posts parent ON p.ParentId = parent.Id
    WHERE p.PostTypeId = 2 
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '18 months'
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) >= 10
),
TagPerformance AS (
    SELECT 
        -- convert tags like '<tag1><tag2>' into array by removing outer <> then splitting on '><'
        string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><') AS tag_array,
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Tags IS NOT NULL
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
UnnestedTags AS (
    SELECT 
        unnest(tag_array) AS tag,
        PostId,
        OwnerUserId,
        Score,
        ViewCount,
        AnswerCount,
        CommentCount
    FROM TagPerformance
),
TagStats AS (
    SELECT 
        ut.tag,
        COUNT(DISTINCT ut.PostId) AS QuestionCount,
        AVG(ut.Score) AS AvgScore,
        AVG(ut.ViewCount) AS AvgViews,
        AVG(ut.AnswerCount) AS AvgAnswers,
        COUNT(DISTINCT ut.OwnerUserId) AS UniqueAskers
    FROM UnnestedTags ut
    GROUP BY ut.tag
    HAVING COUNT(DISTINCT ut.PostId) >= 20
),
UserTagExpertise AS (
    SELECT 
        ut.OwnerUserId,
        ut.tag,
        COUNT(DISTINCT ut.PostId) AS QuestionsInTag,
        AVG(ut.Score) AS AvgScoreInTag,
        RANK() OVER (PARTITION BY ut.tag ORDER BY COUNT(DISTINCT ut.PostId) DESC, AVG(ut.Score) DESC) AS tag_rank
    FROM UnnestedTags ut
    WHERE ut.OwnerUserId IS NOT NULL
    GROUP BY ut.OwnerUserId, ut.tag
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites,
        MIN(v.CreationDate) AS FirstVote,
        MAX(v.CreationDate) AS LastVote
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5)
    GROUP BY v.PostId
),
CommentEngagement AS (
    SELECT 
        c.PostId,
        COUNT(*) AS CommentCount,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        AVG(length(c.Text)) AS AvgCommentLength,
        MAX(c.Score) AS MaxCommentScore
    FROM Comments c
    WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY c.PostId
)
SELECT 
    rau.DisplayName,
    rau.Reputation,
    rau.QuestionCount,
    rau.BadgeCount,
    ROUND(AVG(rau.AvgQuestionScore) OVER (PARTITION BY rau.Id), 2) AS AvgQuestionScore,
    ta.AnswerCount,
    ta.AcceptedCount,
    ROUND(AVG(ta.AvgAnswerScore) OVER (PARTITION BY ta.OwnerUserId), 2) AS AvgAnswerScore,
    ROUND( (CAST(ta.AcceptedCount AS numeric) / NULLIF(ta.AnswerCount, 0) * 100), 2) AS AcceptanceRate,
    ute.tag AS TopTag,
    ute.QuestionsInTag,
    ute.tag_rank AS TagRank,
    ROUND(CAST(ts.AvgScore AS numeric), 2) AS TagAvgScore,
    ts.QuestionCount AS TagTotalQuestions,
    COALESCE(vp.UpVotes, 0) AS TotalUpVotes,
    COALESCE(vp.DownVotes, 0) AS TotalDownVotes,
    COALESCE(ce.CommentCount, 0) AS TotalComments,
    COALESCE(ce.UniqueCommenters, 0) AS UniqueCommenters,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rau.CreationDate))/86400 AS DaysSinceJoined,
    ROUND( (CAST(rau.QuestionCount AS numeric) / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rau.CreationDate))/86400, 0)), 3) AS QuestionsPerDay
FROM RecentActiveUsers rau
LEFT JOIN TopAnswerers ta ON rau.Id = ta.OwnerUserId
LEFT JOIN UserTagExpertise ute ON rau.Id = ute.OwnerUserId AND ute.tag_rank = 1
LEFT JOIN TagStats ts ON ute.tag = ts.tag
LEFT JOIN Posts p ON rau.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN VotePatterns vp ON p.Id = vp.PostId
LEFT JOIN CommentEngagement ce ON p.Id = ce.PostId
WHERE ta.AnswerCount IS NOT NULL
  AND ute.tag IS NOT NULL
ORDER BY 
    (rau.Reputation + (ta.AcceptedCount * 100) + (COALESCE(vp.UpVotes, 0) * 10)) DESC,
    rau.QuestionCount DESC
LIMIT 100;