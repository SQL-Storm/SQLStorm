-- {"query": "46017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 38998, "output_tokens": 31284} 

WITH RECURSIVE UserInfluence AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT b.Id) as BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        t.TagName,
        COUNT(DISTINCT p.Id) as PostsInTag,
        AVG(p.Score) as AvgScore,
        SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as AcceptedAnswers,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT p.Id) DESC, AVG(p.Score) DESC) as ExpertRank
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as TagName
    ) t
    WHERE p.PostTypeId = 2 
        AND p.CreationDate >= NOW() - INTERVAL '18 months'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 5
),
QuestionEngagement AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwnerId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
        COUNT(DISTINCT a.Id) as TotalAnswers,
        MAX(a.Score) as BestAnswerScore,
        COUNT(DISTINCT c.UserId) as UniqueCommenters,
        EXTRACT(EPOCH FROM (MAX(COALESCE(c.CreationDate, a.CreationDate, q.CreationDate)) - q.CreationDate))/3600.0 as HoursToLastActivity
    FROM Posts q
    LEFT JOIN Votes v ON q.Id = v.PostId
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON q.Id = c.PostId OR a.Id = c.PostId
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= NOW() - INTERVAL '1 year'
        AND q.Score >= 5
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.FavoriteCount
),
AnswerQuality AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as IsAccepted,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 as HoursToAnswer,
        COUNT(DISTINCT c.Id) as AnswerComments,
        COUNT(DISTINCT ph.Id) as EditCount,
        LENGTH(a.Body) as AnswerLength,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    LEFT JOIN Comments c ON a.Id = c.PostId
    LEFT JOIN PostHistory ph ON a.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= NOW() - INTERVAL '1 year'
        AND a.OwnerUserId IS NOT NULL
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, q.AcceptedAnswerId, q.CreationDate, a.Body
)
SELECT 
    ui.DisplayName,
    ui.Reputation,
    ui.TotalPostScore,
    ui.QuestionCount,
    ui.AnswerCount,
    ui.BadgeCount,
    te.TagName as TopExpertiseTag,
    te.PostsInTag,
    te.AvgScore as TagAvgScore,
    te.AcceptedAnswers as TagAcceptedAnswers,
    COALESCE(qe.AvgEngagement, 0) as AvgQuestionEngagement,
    COALESCE(aq.AvgAnswerQuality, 0) as AvgAnswerQuality,
    COALESCE(aq.AcceptanceRate, 0) as AnswerAcceptanceRate,
    COALESCE(aq.AvgAnswerSpeed, 0) as AvgHoursToAnswer,
    (ui.Reputation * 0.3 + 
     ui.TotalPostScore * 10 + 
     ui.BadgeCount * 5 + 
     te.AcceptedAnswers * 15 +
     COALESCE(aq.AcceptanceRate, 0) * 100) as InfluenceScore
FROM UserInfluence ui
LEFT JOIN TagExpertise te ON ui.Id = te.OwnerUserId AND te.ExpertRank = 1
LEFT JOIN (
    SELECT 
        QuestionOwnerId,
        AVG(ViewCount * 0.01 + VoteCount * 2 + TotalAnswers * 5 + UniqueCommenters * 3) as AvgEngagement
    FROM QuestionEngagement
    GROUP BY QuestionOwnerId
) qe ON ui.Id = qe.QuestionOwnerId
LEFT JOIN (
    SELECT 
        AnswererUserId,
        AVG(AnswerScore * 2 + IsAccepted * 15 + (6 - LEAST(AnswerRank, 5)) * 3) as AvgAnswerQuality,
        CAST(SUM(IsAccepted) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as AcceptanceRate,
        AVG(HoursToAnswer) as AvgAnswerSpeed
    FROM AnswerQuality
    WHERE AnswerRank <= 5
    GROUP BY AnswererUserId
) aq ON ui.Id = aq.AnswererUserId
WHERE te.TagName IS NOT NULL
ORDER BY InfluenceScore DESC, ui.Reputation DESC
LIMIT 100;
