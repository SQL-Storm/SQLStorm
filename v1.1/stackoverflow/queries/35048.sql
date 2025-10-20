-- {"query": "35048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 891} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT q.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersGiven,
        COALESCE(SUM(v_upvotes.VoteCount), 0) AS TotalUpvotes,
        COALESCE(SUM(v_downvotes.VoteCount), 0) AS TotalDownvotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(u.LastAccessDate) AS LastAccessDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId
    ) v_upvotes ON v_upvotes.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId
    ) v_downvotes ON v_downvotes.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.Id) AS DistinctQuestions,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgQuestionScore
    FROM Tags t
    JOIN Posts p ON 
        t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) 
        AND p.PostTypeId = 1
    WHERE t.Count > 100
    GROUP BY t.TagName, t.Count
),
PopularDuplicates AS (
    SELECT
        pl.RelatedPostId AS OriginalPostId,
        COUNT(pl.PostId) AS DuplicateCount,
        SUM(coalesce(p.Score,0)) AS DuplicatesTotalScore
    FROM PostLinks pl
    JOIN Posts p ON p.Id = pl.PostId
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.RelatedPostId
    HAVING COUNT(pl.PostId) > 5
)
SELECT
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionsAsked,
    tu.AnswersGiven,
    tu.TotalUpvotes,
    tu.TotalDownvotes,
    tu.BadgeCount,
    tu.LastAccessDate,
    tt.TagName AS MostUsedTag,
    tt.TagUsageCount,
    tt.DistinctQuestions,
    tt.TotalScore AS TagTotalScore,
    tt.AvgQuestionScore AS TagAvgScore,
    pd.DuplicateCount AS TimesAsDuplicateOrigin,
    pd.DuplicatesTotalScore AS DuplicatesTotalScore
FROM TopUsers tu
LEFT JOIN Posts p ON p.OwnerUserId = tu.UserId AND p.PostTypeId = 1
LEFT JOIN LATERAL (
    SELECT 
        t.TagName, 
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p2.Id) AS DistinctQuestions,
        SUM(p2.Score) AS TotalScore,
        AVG(p2.Score) AS AvgQuestionScore
    FROM Tags t
    JOIN Posts p2 ON 
        t.TagName = ANY(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) 
        AND p2.PostTypeId = 1
        AND p2.OwnerUserId = tu.UserId
    WHERE t.Count > 100
    GROUP BY t.TagName, t.Count
    ORDER BY COUNT(DISTINCT p2.Id) DESC, SUM(p2.Score) DESC
    LIMIT 1
) tt ON TRUE
LEFT JOIN PopularDuplicates pd ON pd.OriginalPostId = p.Id
ORDER BY tu.Reputation DESC, tu.TotalUpvotes DESC
LIMIT 50;