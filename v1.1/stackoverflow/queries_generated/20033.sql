-- {"query": "20033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1830} 

WITH PostTags AS (
    -- CTE to normalize tags for each question post, using a lateral join to unnest the tag string.
    -- This is often a performance-intensive operation on large text fields.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.FavoriteCount,
        tag.name AS TagName
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag(name)
    WHERE p.PostTypeId = 1 -- Questions
      AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
),
UserContentAggregates AS (
    -- Aggregate user-level stats using a UNION ALL to combine different content types (Questions vs Answers).
    -- This tests the performance of set operators and subquery aggregation.
    SELECT
        OwnerUserId AS UserId,
        SUM(AnswerCount) AS TotalAnswersPosted,
        SUM(QuestionCount) AS TotalQuestionsAsked,
        SUM(ContentScore) AS TotalContentScore,
        SUM(DownVotesOnContent) AS TotalDownVotesOnContent
    FROM (
        -- User's Answers
        SELECT
            a.OwnerUserId,
            1 AS AnswerCount,
            0 AS QuestionCount,
            a.Score AS ContentScore,
            -- Correlated subquery to count downvotes per post
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3) AS DownVotesOnContent
        FROM Posts a
        WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
        UNION ALL
        -- User's Questions
        SELECT
            q.OwnerUserId,
            0 AS AnswerCount,
            1 AS QuestionCount,
            q.Score AS ContentScore,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotesOnContent
        FROM Posts q
        WHERE q.PostTypeId = 1 AND q.OwnerUserId IS NOT NULL
    ) AS UserPostActivity
    GROUP BY OwnerUserId
),
UserTagPerformance AS (
    -- Calculate detailed user performance per tag, including scores, answer counts, and tag-specific badges.
    SELECT
        ans.OwnerUserId,
        pt.TagName,
        COUNT(ans.Id) AS AnswersInTag,
        SUM(ans.Score) AS TotalScoreInTag,
        AVG(ans.CommentCount) AS AvgCommentsPerAnswer,
        -- Correlated subquery to count tag-specific badges for the user, demonstrating a complex predicate.
        (SELECT COUNT(*)
         FROM Badges b
         WHERE b.UserId = ans.OwnerUserId
           AND b.TagBased = B'1'
           AND lower(b.Name) = lower(pt.TagName)
           AND b.Class = 1 -- Only Gold badges
        ) AS GoldTagBadges
    FROM Posts ans
    -- Join answers to their questions to determine the tags.
    JOIN PostTags pt ON ans.ParentId = pt.PostId
    WHERE ans.PostTypeId = 2 -- Answers
      AND ans.OwnerUserId IS NOT NULL
    GROUP BY ans.OwnerUserId, pt.TagName
    HAVING COUNT(ans.Id) > 10 AND SUM(ans.Score) > 100 -- Filter for users with significant contributions in a tag.
),
RankedTagPerformance AS (
    -- Use window functions to rank users within each tag and calculate relative performance metrics.
    SELECT
        utp.OwnerUserId,
        utp.TagName,
        utp.AnswersInTag,
        utp.TotalScoreInTag,
        utp.GoldTagBadges,
        -- Rank users within each tag by a composite score based on answers, score, and badges.
        DENSE_RANK() OVER (PARTITION BY utp.TagName ORDER BY (utp.TotalScoreInTag + utp.AnswersInTag * 10 + utp.GoldTagBadges * 100) DESC) AS TagRank,
        -- Calculate the difference in score from the previously-ranked user in the same tag using LAG.
        utp.TotalScoreInTag - LAG(utp.TotalScoreInTag, 1, 0) OVER (PARTITION BY utp.TagName ORDER BY (utp.TotalScoreInTag + utp.AnswersInTag * 10 + utp.GoldTagBadges * 100) DESC) AS ScoreDiffFromPrevRank
    FROM UserTagPerformance utp
),
ContentChurn AS (
    -- Analyze post history to measure how much a user's content is edited, debated, or closed.
    SELECT
        p.OwnerUserId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS TotalEditsAndRollbacks,
        -- Calculate the average time between a post's creation and its first closure, if any.
        AVG(CASE WHEN ph.PostHistoryTypeId = 10 THEN AGE(ph.CreationDate, p.CreationDate) ELSE NULL END) AS AvgTimeToFirstClosure
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.OwnerUserId IS NOT NULL
      AND ph.CreationDate > p.CreationDate -- Exclude initial creation events
    GROUP BY p.OwnerUserId
)
-- Final SELECT statement joining all CTEs to present a comprehensive report on top users.
-- This uses outer joins to handle users who may not have data in all aggregated CTEs.
SELECT
    u.DisplayName,
    u.Reputation,
    rtp.TagName,
    rtp.TagRank,
    rtp.AnswersInTag,
    rtp.TotalScoreInTag,
    rtp.ScoreDiffFromPrevRank,
    COALESCE(uca.TotalDownVotesOnContent, 0) AS DownVotesReceived,
    -- Complex CASE expression for user categorization based on multiple performance and activity metrics.
    CASE
        WHEN rtp.TagRank <= 3 AND rtp.GoldTagBadges > 0 THEN 'Elite Tag Specialist'
        WHEN rtp.TagRank <= 10 AND uca.TotalDownVotesOnContent > 50 THEN 'Controversial Expert'
        WHEN u.Reputation > 100000 AND rtp.AnswersInTag > 50 THEN 'Community Pillar'
        ELSE 'Dedicated Contributor'
    END AS UserProfile,
    -- String manipulation and NULL logic to create a summary string.
    CONCAT_WS(' | ',
        'Location: ' || COALESCE(u.Location, 'N/A'),
        'Active Since: ' || TO_CHAR(u.CreationDate, 'YYYY'),
        'Content Edits: ' || COALESCE(cc.TotalEditsAndRollbacks, 0)
    ) AS UserSummary,
    cc.AvgTimeToFirstClosure
FROM Users u
JOIN RankedTagPerformance rtp ON u.Id = rtp.OwnerUserId
LEFT JOIN UserContentAggregates uca ON u.Id = uca.UserId
LEFT JOIN ContentChurn cc ON u.Id = cc.OwnerUserId
WHERE
    u.Reputation > 20000 -- Filter for high-reputation users.
    AND u.CreationDate < (NOW() - INTERVAL '4 years') -- Filter for established users.
    AND rtp.TagRank <= 50 -- Only consider the top 50 experts in each tag.
    AND EXISTS ( -- Use a correlated EXISTS subquery to check for highly-scored comments, a sign of valued interaction.
        SELECT 1
        FROM Comments c
        WHERE c.UserId = u.Id AND c.Score > 20
    )
ORDER BY
    rtp.TagName,
    rtp.TagRank,
    u.Reputation DESC
LIMIT 500;
