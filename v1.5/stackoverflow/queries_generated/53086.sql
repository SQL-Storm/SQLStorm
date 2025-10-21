-- {"query": "53086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 743} 

WITH GoldBadgeUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(b.Id) AS GoldBadgeCount
    FROM 
        Users u
    JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        b.Class = 1
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(b.Id) >= 5
),
TaggedQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.ViewCount,
        p.AcceptedAnswerId
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1 
        AND t.TagName IN ('sql', 'database', 'performance')
        AND p.CreationDate >= '2020-01-01'
),
UserAnswers AS (
    SELECT 
        a.OwnerUserId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        q.QuestionId,
        q.ViewCount,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts a
    JOIN 
        TaggedQuestions q ON a.ParentId = q.QuestionId
    LEFT JOIN 
        Comments c ON a.Id = c.PostId
    WHERE 
        a.PostTypeId = 2
        AND a.Score > 0
    GROUP BY 
        a.OwnerUserId, a.Id, a.Score, q.QuestionId, q.ViewCount
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) AS UpvoteCount
    FROM 
        Votes v
    WHERE 
        v.VoteTypeId = 2
    GROUP BY 
        v.UserId
),
ElaborateUserStats AS (
    SELECT 
        gbu.UserId,
        gbu.Reputation,
        gbu.GoldBadgeCount,
        COUNT(ua.AnswerId) AS HighViewAnswerCount,
        AVG(ua.AnswerScore) AS AvgAnswerScore,
        SUM(ua.CommentCount) AS TotalComments,
        MAX(ua.ViewCount) AS MaxQuestionViews,
        COALESCE(uv.UpvoteCount, 0) AS TotalUpvotesReceived,
        ROW_NUMBER() OVER (PARTITION BY gbu.GoldBadgeCount ORDER BY COUNT(ua.AnswerId) DESC) AS RankWithinGroup
    FROM 
        GoldBadgeUsers gbu
    LEFT JOIN 
        UserAnswers ua ON gbu.UserId = ua.OwnerUserId
    LEFT JOIN 
        UserVotes uv ON gbu.UserId = uv.UserId
    WHERE 
        ua.ViewCount > 100
    GROUP BY 
        gbu.UserId, gbu.Reputation, gbu.GoldBadgeCount, uv.UpvoteCount
)
SELECT 
    eus.UserId,
    eus.Reputation,
    eus.GoldBadgeCount,
    eus.HighViewAnswerCount,
    eus.AvgAnswerScore,
    eus.TotalComments,
    eus.MaxQuestionViews,
    eus.TotalUpvotesReceived,
    eus.RankWithinGroup,
    (SELECT COUNT(ph.Id) 
     FROM PostHistory ph 
     WHERE ph.UserId = eus.UserId 
     AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
FROM 
    ElaborateUserStats eus
WHERE 
    eus.RankWithinGroup <= 5
ORDER BY 
    eus.GoldBadgeCount DESC, 
    eus.HighViewAnswerCount DESC
LIMIT 50;
