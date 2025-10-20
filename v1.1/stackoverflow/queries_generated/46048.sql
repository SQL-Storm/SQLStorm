-- {"query": "46048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 110112, "output_tokens": 90035} 

WITH TopQuestionAskers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgQuestionScore,
        SUM(p.ViewCount) as TotalViews
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
        AND p.Score > 5
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as QuestionId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        MAX(a.Score) as BestAnswerScore,
        AVG(a.Score) as AvgAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) as UniqueAnswerers,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as HasAcceptedAnswer
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY a.ParentId
),
TagEngagement AS (
    SELECT 
        t.TagName,
        t.Count as TagUsageCount,
        COUNT(DISTINCT b.UserId) as ExpertsWithBadges,
        AVG(p.Score) as AvgTagQuestionScore,
        COUNT(DISTINCT c.Id) as TotalComments
    FROM Tags t
    LEFT JOIN Posts p ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    LEFT JOIN Badges b ON t.TagName = b.Name AND b.TagBased = 1
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) >= 100
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as Favorites,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as MaxBounty,
        COUNT(DISTINCT v.UserId) as UniqueVoters
    FROM Votes v
    WHERE v.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY v.PostId
)
SELECT 
    tqa.DisplayName,
    tqa.Reputation,
    tqa.QuestionCount,
    ROUND(tqa.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    tqa.TotalViews,
    te.TagName as MostActiveTag,
    te.AvgTagQuestionScore,
    te.ExpertsWithBadges,
    am.AnswerCount,
    am.BestAnswerScore,
    ROUND(am.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    am.UniqueAnswerers,
    vp.UpVotes,
    vp.DownVotes,
    vp.Favorites,
    vp.MaxBounty,
    vp.UniqueVoters,
    COUNT(DISTINCT ph.Id) as EditHistoryCount,
    COUNT(DISTINCT c.Id) as CommentCount,
    ROUND((vp.UpVotes::numeric / NULLIF(vp.UpVotes + vp.DownVotes, 0)) * 100, 2) as PositiveVotePercentage
FROM TopQuestionAskers tqa
JOIN Posts p ON p.OwnerUserId = tqa.Id AND p.PostTypeId = 1
LEFT JOIN AnswerMetrics am ON am.QuestionId = p.Id
LEFT JOIN VotePatterns vp ON vp.PostId = p.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN LATERAL (
    SELECT te2.TagName, te2.AvgTagQuestionScore, te2.ExpertsWithBadges
    FROM TagEngagement te2
    WHERE te2.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    ORDER BY te2.AvgTagQuestionScore DESC
    LIMIT 1
) te ON true
WHERE vp.UpVotes > 10
    AND am.AnswerCount >= 2
GROUP BY 
    tqa.DisplayName, tqa.Reputation, tqa.QuestionCount, tqa.AvgQuestionScore, 
    tqa.TotalViews, te.TagName, te.AvgTagQuestionScore, te.ExpertsWithBadges,
    am.AnswerCount, am.BestAnswerScore, am.AvgAnswerScore, am.UniqueAnswerers,
    vp.UpVotes, vp.DownVotes, vp.Favorites, vp.MaxBounty, vp.UniqueVoters
HAVING COUNT(DISTINCT ph.Id) >= 3
ORDER BY tqa.Reputation DESC, vp.UpVotes DESC, am.BestAnswerScore DESC
LIMIT 100;
