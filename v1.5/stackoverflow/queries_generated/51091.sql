-- {"query": "51091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1652} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN pt.Id = 1 THEN p.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN pt.Id = 2 THEN p.Id END) AS AnswersPosted,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id 
                      AND p.PostTypeId IN (1, 2)  -- Questions and Answers only
                      AND p.CreationDate >= NOW() - INTERVAL '1 year'
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON v.PostId = p.Id 
                     AND v.VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
                     AND v.CreationDate >= NOW() - INTERVAL '6 months'
    LEFT JOIN Badges b ON b.UserId = u.Id 
                      AND b.Date >= NOW() - INTERVAL '1 year'
    WHERE u.Reputation >= 100 
      AND u.CreationDate >= NOW() - INTERVAL '2 years'
      AND u.LastAccessDate >= NOW() - INTERVAL '30 days'
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) >= 5  -- Users who have posted at least 5 times
),
TopTagsByUser AS (
    SELECT 
        au.UserId,
        au.Reputation,
        t.TagName,
        COUNT(*) AS TagUsageCount,
        AVG(p.Score) AS AvgTagScore,
        ROW_NUMBER() OVER (PARTITION BY au.UserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM ActiveUsers au
    JOIN Posts p ON p.OwnerUserId = au.UserId 
                AND p.PostTypeId = 1  -- Questions only
                AND p.CreationDate >= NOW() - INTERVAL '6 months'
    JOIN Tags t ON string_to_array(
        substring(p.Tags, 2, length(p.Tags)-2), 
        '><'
    ) @> ARRAY[t.TagName]::text[]  -- Using array containment for tag matching
    GROUP BY au.UserId, au.Reputation, t.TagName
),
QuestionEngagement AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate AS QuestionDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(accepted.Id, 0) AS AcceptedAnswerId,
        AVG(ans.Score) AS AvgAnswerScore,
        COUNT(DISTINCT ans.OwnerUserId) AS DistinctAnswerers,
        SUM(CASE WHEN va.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalQuestionUpvotes,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
            ELSE 'Open'
        END AS QuestionStatus
    FROM Posts p
    LEFT JOIN Posts accepted ON p.AcceptedAnswerId = accepted.Id
    LEFT JOIN Posts ans ON p.Id = ans.ParentId 
                        AND ans.PostTypeId = 2 
                        AND ans.CreationDate <= p.LastActivityDate
    LEFT JOIN Votes va ON va.PostId = p.Id 
                       AND va.VoteTypeId = 2  -- Upvotes on questions
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id 
                            AND ph.PostHistoryTypeId IN (10, 11)  -- Close/Reopen
                            AND ph.CreationDate = (
                                SELECT MAX(ph2.CreationDate) 
                                FROM PostHistory ph2 
                                WHERE ph2.PostId = p.Id 
                                AND ph2.PostHistoryTypeId IN (10, 11)
                            )
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= NOW() - INTERVAL '3 months'
      AND p.Score >= -5  -- Exclude heavily downvoted questions
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, 
             p.AnswerCount, p.CommentCount, accepted.Id, p.ClosedDate, 
             ph.PostHistoryTypeId
),
ComplexInteractions AS (
    SELECT 
        au.UserId,
        au.TotalPosts,
        au.AvgPostScore,
        au.TotalUpvotesReceived,
        tt.TagName AS PrimaryTag,
        qe.QuestionScore,
        qe.ViewCount,
        qe.AnswerCount,
        qe.AvgAnswerScore,
        qe.QuestionStatus,
        -- Calculate engagement ratio
        (qe.ViewCount * 1.0 / NULLIF(qe.AnswerCount, 0)) AS ViewPerAnswerRatio,
        -- Net vote score for user
        (au.TotalUpvotesReceived - au.TotalDownvotesReceived) AS NetVotes,
        -- Time-based engagement score
        EXTRACT(EPOCH FROM (NOW() - au.UserCreationDate)) / 86400 AS UserAgeDays,
        -- Complex correlation: badge count weighted by tag performance
        au.TotalBadges * tt.TagUsageCount * qe.QuestionScore AS EngagementScore,
        ROW_NUMBER() OVER (
            PARTITION BY tt.TagName 
            ORDER BY (au.Reputation * qe.ViewCount * qe.AnswerCount) DESC
        ) AS RankWithinTag
    FROM ActiveUsers au
    JOIN TopTagsByUser tt ON au.UserId = tt.UserId AND tt.TagRank <= 3
    JOIN QuestionEngagement qe ON au.UserId = qe.OwnerUserId
    WHERE qe.QuestionDate >= NOW() - INTERVAL '1 month'
      AND qe.AnswerCount >= 1
      AND tt.TagUsageCount >= 3
)
SELECT 
    ci.PrimaryTag,
    COUNT(DISTINCT ci.UserId) AS ActiveUsersInTag,
    AVG(ci.Reputation) AS AvgUserReputation,
    AVG(ci.TotalPosts) AS AvgPostsPerUser,
    AVG(ci.AvgPostScore) AS AvgPostScore,
    AVG(ci.NetVotes) AS AvgNetVotes,
    AVG(ci.ViewPerAnswerRatio) AS AvgViewAnswerRatio,
    AVG(ci.EngagementScore) AS AvgEngagementScore,
    -- Performance-intensive aggregations
    SUM(ci.ViewCount) AS TotalViewsInTag,
    SUM(ci.AnswerCount) AS TotalAnswersInTag,
    COUNT(CASE WHEN ci.QuestionStatus = 'Open' THEN 1 END) AS OpenQuestions,
    COUNT(CASE WHEN ci.QuestionStatus = 'Closed' THEN 1 END) AS ClosedQuestions,
    -- Percentile calculations for benchmarking
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ci.Reputation) AS MedianReputation,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY ci.ViewCount) AS P90Views,
    -- Complex window function for ranking
    COUNT(*) OVER () AS TotalRows,
    RANK() OVER (ORDER BY AVG(ci.EngagementScore) DESC) AS TagEngagementRank
FROM ComplexInteractions ci
WHERE ci.RankWithinTag <= 5  -- Top 5 users per tag
  AND ci.UserAgeDays >= 30
  AND ci.EngagementScore > 0
GROUP BY ci.PrimaryTag
HAVING AVG(ci.Reputation) >= 500
ORDER BY AvgEngagementScore DESC
LIMIT 20;
