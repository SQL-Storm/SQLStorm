WITH TopQuestionAskers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViews
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
        a.ParentId AS QuestionId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        MAX(a.Score) AS BestAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) AS UniqueAnswerers,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY a.ParentId
),
TagEngagement AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT b.UserId) AS ExpertsWithBadges,
        AVG(p.Score) AS AvgTagQuestionScore,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM Tags t
    LEFT JOIN Posts p ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    LEFT JOIN Badges b ON t.TagName = b.Name AND CAST(b.TagBased AS INTEGER) = 1
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) >= 100
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS MaxBounty,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes v
    WHERE v.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY v.PostId
)
SELECT 
    tqa.DisplayName,
    tqa.Reputation,
    tqa.QuestionCount,
    ROUND(CAST(tqa.AvgQuestionScore AS NUMERIC), 2) AS AvgQuestionScore,
    tqa.TotalViews,
    te.TagName AS MostActiveTag,
    te.AvgTagQuestionScore,
    te.ExpertsWithBadges,
    am.AnswerCount,
    am.BestAnswerScore,
    ROUND(CAST(am.AvgAnswerScore AS NUMERIC), 2) AS AvgAnswerScore,
    am.UniqueAnswerers,
    vp.UpVotes,
    vp.DownVotes,
    vp.Favorites,
    vp.MaxBounty,
    vp.UniqueVoters,
    COUNT(DISTINCT ph.Id) AS EditHistoryCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    ROUND((CAST(vp.UpVotes AS NUMERIC) / NULLIF(CAST(vp.UpVotes + vp.DownVotes AS NUMERIC), 0)) * 100, 2) AS PositiveVotePercentage
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