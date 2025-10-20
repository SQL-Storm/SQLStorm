-- {"query": "46002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 4588, "output_tokens": 3256} 

WITH RecentActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           COUNT(DISTINCT p.Id) as QuestionCount,
           COUNT(DISTINCT b.Id) as BadgeCount,
           AVG(p.Score) as AvgQuestionScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) >= 5
),
TopAnswerers AS (
    SELECT p.OwnerUserId, 
           COUNT(*) as AnswerCount,
           SUM(CASE WHEN p.Id = parent.AcceptedAnswerId THEN 1 ELSE 0 END) as AcceptedCount,
           AVG(p.Score) as AvgAnswerScore,
           MAX(p.CreationDate) as LastAnswerDate
    FROM Posts p
    INNER JOIN Posts parent ON p.ParentId = parent.Id
    WHERE p.PostTypeId = 2 
      AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '18 months'
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) >= 10
),
TagPerformance AS (
    SELECT 
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array,
        p.Id as PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Tags IS NOT NULL
      AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
),
UnnestedTags AS (
    SELECT 
        unnest(tag_array) as tag,
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
        COUNT(DISTINCT ut.PostId) as QuestionCount,
        AVG(ut.Score) as AvgScore,
        AVG(ut.ViewCount) as AvgViews,
        AVG(ut.AnswerCount) as AvgAnswers,
        COUNT(DISTINCT ut.OwnerUserId) as UniqueAskers
    FROM UnnestedTags ut
    GROUP BY ut.tag
    HAVING COUNT(DISTINCT ut.PostId) >= 20
),
UserTagExpertise AS (
    SELECT 
        ut.OwnerUserId,
        ut.tag,
        COUNT(DISTINCT ut.PostId) as QuestionsInTag,
        AVG(ut.Score) as AvgScoreInTag,
        RANK() OVER (PARTITION BY ut.tag ORDER BY COUNT(DISTINCT ut.PostId) DESC, AVG(ut.Score) DESC) as tag_rank
    FROM UnnestedTags ut
    WHERE ut.OwnerUserId IS NOT NULL
    GROUP BY ut.OwnerUserId, ut.tag
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as Favorites,
        MIN(v.CreationDate) as FirstVote,
        MAX(v.CreationDate) as LastVote
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5)
    GROUP BY v.PostId
),
CommentEngagement AS (
    SELECT 
        c.PostId,
        COUNT(*) as CommentCount,
        COUNT(DISTINCT c.UserId) as UniqueCommenters,
        AVG(LENGTH(c.Text)) as AvgCommentLength,
        MAX(c.Score) as MaxCommentScore
    FROM Comments c
    WHERE c.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY c.PostId
)
SELECT 
    rau.DisplayName,
    rau.Reputation,
    rau.QuestionCount,
    rau.BadgeCount,
    ROUND(rau.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    ta.AnswerCount,
    ta.AcceptedCount,
    ROUND(ta.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    ROUND((ta.AcceptedCount::float / NULLIF(ta.AnswerCount, 0) * 100)::numeric, 2) as AcceptanceRate,
    ute.tag as TopTag,
    ute.QuestionsInTag,
    ute.tag_rank as TagRank,
    ROUND(ts.AvgScore::numeric, 2) as TagAvgScore,
    ts.QuestionCount as TagTotalQuestions,
    COALESCE(vp.UpVotes, 0) as TotalUpVotes,
    COALESCE(vp.DownVotes, 0) as TotalDownVotes,
    COALESCE(ce.CommentCount, 0) as TotalComments,
    COALESCE(ce.UniqueCommenters, 0) as UniqueCommenters,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - rau.CreationDate))/86400 as DaysSinceJoined,
    ROUND((rau.QuestionCount::float / NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - rau.CreationDate))/86400, 0))::numeric, 3) as QuestionsPerDay
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
