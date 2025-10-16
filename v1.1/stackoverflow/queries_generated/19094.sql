-- {"query": "19094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3216} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates various engagement metrics for users focusing on recent activity.
    -- It includes counts of posts, comments, and post history entries, along with sum of given votes.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwnedCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwnedCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostsScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEntries,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        MAX(u.LastAccessDate) AS UserLastActivityDate,
        -- String expression and NULL logic: Extracts a part of the location, handles NULL AboutMe.
        COALESCE(SUBSTRING(u.Location, 1, 50), 'Unknown Region') AS UserLocationSnippet,
        LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= (CURRENT_DATE - INTERVAL '3 years')
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= (CURRENT_DATE - INTERVAL '3 years')
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.CreationDate >= (CURRENT_DATE - INTERVAL '3 years')
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.CreationDate >= (CURRENT_DATE - INTERVAL '3 years')
    WHERE u.CreationDate >= (CURRENT_DATE - INTERVAL '5 years') -- Filter for users created in the last 5 years
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Location, u.AboutMe
),
QuestionDetails AS (
    -- CTE 2: Gathers comprehensive details for 'Question' posts, including edit history and accepted answers.
    -- Focuses on questions related to "SQL", "Database", or "Performance" within a recent timeframe.
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreationDate,
        q.LastActivityDate AS QuestionLastActivityDate,
        q.LastEditDate AS QuestionLastEditDate,
        q.ClosedDate AS QuestionClosedDate,
        -- Complicated Predicates/Expressions/Calculations: Counts specific edit types from PostHistory.
        (SELECT COUNT(DISTINCT ph_edit.Id)
         FROM PostHistory ph_edit
         WHERE ph_edit.PostId = q.Id
           AND ph_edit.PostHistoryTypeId IN (4, 5, 6, 8, 9, 10, 11, 12, 13)) AS SignificantEditOrStatusChangeCount,
        -- String expression: Cleans and formats tags for easier parsing.
        REPLACE(REPLACE(REPLACE(q.Tags, '><', ','), '<', ''), '>', '') AS CleanedTags,
        -- Outer Join with Posts for Accepted Answer details.
        aa.Id AS AcceptedAnswerId,
        aa.Score AS AcceptedAnswerScore,
        aa.OwnerUserId AS AcceptedAnswerOwnerId,
        aa.CreationDate AS AcceptedAnswerCreationDate,
        -- Correlated Subquery: Checks if the question has a 'Duplicate' link.
        EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3) AS HasDuplicateLink,
        -- Null Logic: Determine if an accepted answer exists and its age.
        CASE WHEN aa.Id IS NOT NULL THEN EXTRACT(DAY FROM (q.CreationDate - aa.CreationDate)) ELSE NULL END AS DaysToAcceptedAnswer
    FROM Posts q
    LEFT JOIN Posts aa ON q.AcceptedAnswerId = aa.Id AND aa.PostTypeId = 2 -- Ensure accepted is an answer
    WHERE q.PostTypeId = 1 -- Only questions
      AND q.CreationDate >= (CURRENT_DATE - INTERVAL '2 years') -- Recent questions
      AND (q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<database>%' OR q.Tags LIKE '%<performance>%') -- Focus on relevant topics
),
RankedAndAggregatedUsers AS (
    -- CTE 3: Ranks users based on their engagement and post scores using window functions.
    -- Also calculates average question scores and cumulative accepted answer scores.
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalPostsOwned,
        ue.QuestionsOwnedCount,
        ue.AnswersOwnedCount,
        ue.TotalPostsScore,
        ue.TotalCommentsMade,
        ue.UserLastActivityDate,
        ue.UserLocationSnippet,
        -- Window function: Ranks users by reputation within tiers defined by their post count.
        RANK() OVER (PARTITION BY (CASE WHEN ue.TotalPostsOwned >= 100 THEN 'Elite' WHEN ue.TotalPostsOwned >= 25 THEN 'Active' ELSE 'Contributor' END) ORDER BY ue.Reputation DESC, ue.UserLastActivityDate DESC) AS RankInPostTier,
        -- Window function: Calculates the average score of questions owned by the user.
        COALESCE(AVG(qd.QuestionScore) OVER (PARTITION BY ue.UserId), 0) AS AvgQuestionScoreOwned,
        -- Window function: Calculates the cumulative sum of scores of accepted answers owned by the user.
        COALESCE(SUM(qd.AcceptedAnswerScore) OVER (PARTITION BY ue.UserId ORDER BY qd.AcceptedAnswerCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) AS CumulativeAcceptedAnswerScore,
        -- Correlated Subquery for additional user-specific metric: Average view count of their *answered* questions.
        (SELECT COALESCE(AVG(p_ans.ViewCount), 0)
         FROM Posts p_ans
         WHERE p_ans.Id IN (SELECT qd_inner.QuestionId FROM QuestionDetails qd_inner WHERE qd_inner.AcceptedAnswerOwnerId = ue.UserId)
           AND p_ans.PostTypeId = 1) AS AvgViewCountOnAnsweredQuestions
    FROM UserEngagement ue
    INNER JOIN QuestionDetails qd ON ue.UserId = qd.QuestionOwnerId OR ue.UserId = qd.AcceptedAnswerOwnerId
    WHERE ue.TotalPostsOwned > 0
),
UserBadgeSummary AS (
    -- CTE 4: Summarizes badge information for users, categorizing by class and identifying specific tag badges.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Complicated Predicates/Expressions/Calculations: Flags users with specific "SQL" related tag badges.
        MAX(CASE WHEN b.TagBased = TRUE AND (LOWER(b.Name) LIKE '%sql%' OR LOWER(b.Name) LIKE '%database%') THEN 1 ELSE 0 END) AS HasRelevantTagBadge
    FROM Badges b
    INNER JOIN UserEngagement ue ON b.UserId = ue.UserId
    WHERE b.Date >= (CURRENT_DATE - INTERVAL '2 years')
    GROUP BY b.UserId
)
-- Main query: Combines information from all CTEs, applies complex filters, and includes a set operator.
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.TotalPostsOwned,
    rau.QuestionsOwnedCount,
    rau.AnswersOwnedCount,
    rau.TotalPostsScore,
    rau.TotalCommentsMade,
    rau.UserLastActivityDate,
    rau.RankInPostTier,
    rau.AvgQuestionScoreOwned,
    rau.CumulativeAcceptedAnswerScore,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.HasRelevantTagBadge,
    rau.AvgViewCountOnAnsweredQuestions,
    -- String expression: Creates a unique user identifier.
    'USER#' || SUBSTRING(rau.DisplayName, 1, 3) || '-' || LPAD(rau.UserId::text, 7, '0') AS UserHashId,
    -- NULL logic: Uses COALESCE for AboutMeLength.
    COALESCE(ue.AboutMeLength, 0) AS UserAboutMeContentLength,
    -- Nested Correlated Subquery: Calculates the average score of specific answers provided by the user.
    -- This inner query looks for answers where the parent question contains 'optimize' and the answer itself
    -- has a score greater than the average score of all answers for that specific parent question.
    (
        SELECT COALESCE(AVG(ans.Score), 0)
        FROM Posts ans
        WHERE ans.OwnerUserId = rau.UserId
          AND ans.PostTypeId = 2 -- Must be an answer
          AND EXISTS (
                SELECT 1
                FROM Posts q_inner
                WHERE q_inner.Id = ans.ParentId
                  AND q_inner.Title ILIKE '%optimize%'
                  AND ans.Score > (SELECT COALESCE(AVG(ans_avg.Score), 0) FROM Posts ans_avg WHERE ans_avg.ParentId = q_inner.Id)
            )
    ) AS AvgOptimizingAnswerScore
FROM RankedAndAggregatedUsers rau
INNER JOIN UserEngagement ue ON rau.UserId = ue.UserId -- Re-join for AboutMeLength from base CTE
LEFT JOIN UserBadgeSummary ubs ON rau.UserId = ubs.UserId
WHERE
    rau.RankInPostTier <= 20 -- Top users in their tiers
    AND rau.AvgQuestionScoreOwned > 5 -- Questions must have a decent average score
    AND (ubs.HasRelevantTagBadge = 1 OR ubs.GoldBadges > 0) -- Users must have relevant tag badge or at least one Gold badge
    AND ue.AboutMeLength > 50 -- Users with some 'About Me' content
    AND rau.CumulativeAcceptedAnswerScore > 100 -- Users with significant accepted answer impact
ORDER BY
    rau.Reputation DESC,
    rau.UserLastActivityDate DESC
LIMIT 100

UNION ALL

-- Set Operator (UNION ALL): This branch identifies highly viewed and actively edited questions
-- that are either closed as duplicates or lack an accepted answer, focusing on 'tuning' or 'indexing'.
SELECT
    qd.QuestionOwnerId AS UserId,
    COALESCE(u.DisplayName, 'Community User') AS DisplayName, -- NULL logic for deleted or community-owned users
    COALESCE(u.Reputation, 0) AS Reputation,
    COALESCE(ue_sub.TotalPostsOwned, 0) AS TotalPostsOwned,
    COALESCE(ue_sub.QuestionsOwnedCount, 0) AS QuestionsOwnedCount,
    COALESCE(ue_sub.AnswersOwnedCount, 0) AS AnswersOwnedCount,
    COALESCE(ue_sub.TotalPostsScore, 0) AS TotalPostsScore,
    COALESCE(ue_sub.TotalCommentsMade, 0) AS TotalCommentsMade,
    qd.QuestionLastActivityDate AS UserLastActivityDate, -- Using question activity date here
    NULL AS RankInPostTier, -- Not applicable for question-centric results
    qd.QuestionScore AS AvgQuestionScoreOwned, -- Using question score directly for this branch
    COALESCE(qd.AcceptedAnswerScore, 0) AS CumulativeAcceptedAnswerScore, -- Using accepted answer score directly
    NULL AS TotalBadges, NULL AS GoldBadges, NULL AS SilverBadges, NULL AS BronzeBadges, NULL AS HasRelevantTagBadge,
    NULL AS AvgViewCountOnAnsweredQuestions, -- Not applicable
    'QUES#' || SUBSTRING(qd.QuestionTitle, 1, 3) || '-' || LPAD(qd.QuestionId::text, 7, '0') AS UserHashId,
    NULL AS UserAboutMeContentLength, -- Not applicable
    -- Correlated Subquery: Calculates the average score of all answers for this specific question.
    (
        SELECT COALESCE(AVG(ans.Score), 0)
        FROM Posts ans
        WHERE ans.ParentId = qd.QuestionId
          AND ans.PostTypeId = 2
    ) AS AvgOptimizingAnswerScore
FROM QuestionDetails qd
LEFT JOIN Users u ON qd.QuestionOwnerId = u.Id
LEFT JOIN UserEngagement ue_sub ON qd.QuestionOwnerId = ue_sub.UserId -- Join to get base user stats for owner
WHERE
    (qd.QuestionTitle ILIKE '%tuning%' OR qd.QuestionTitle ILIKE '%indexing%')
    AND qd.ViewCount > 10000 -- Highly viewed questions
    AND qd.SignificantEditOrStatusChangeCount > 5 -- Sign of significant community interaction/revision
    AND (qd.AcceptedAnswerId IS NULL OR qd.HasDuplicateLink = TRUE) -- Either no accepted answer or it's a duplicate
    AND qd.QuestionClosedDate IS NULL -- Still open for discussion/answers, even if duplicate-linked
ORDER BY
    Reputation DESC,
    UserLastActivityDate DESC
LIMIT 50;
