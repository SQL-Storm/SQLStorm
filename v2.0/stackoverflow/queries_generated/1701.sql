-- {"query": "1701.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3252} 

WITH UserActivitySummary AS (
    -- CTE 1: Aggregates user activity, badge counts, and calculates average scores for questions/answers.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS UserLocation, -- NULL logic: Provide default for missing location
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COUNT(DISTINCT c.Id) AS CommentsMadeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        -- Window function: Calculate median view count for questions posted by this user
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS MedianQuestionViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation >= 1000 AND u.LastAccessDate >= '2023-01-01' -- Filter users by reputation and recent activity
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
    HAVING COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) >= 5 -- Filter users with at least 5 questions
),
QuestionPerformance AS (
    -- CTE 2: Analyzes performance of questions, extracts primary tags, and uses correlated subqueries and window functions.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount AS QuestionCommentCount,
        q.FavoriteCount,
        -- String expression: Extract the primary tag from the 'Tags' string. Assumes format <tag1><tag2>...
        (string_to_array(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><'))[1] AS PrimaryTag,
        -- Complicated calculation: Normalized view-to-score ratio, handling potential division by zero
        CASE
            WHEN q.ViewCount > 100 THEN (q.Score * 1.0 / q.ViewCount) * 100
            ELSE 0.0
        END AS NormalizedScorePer100Views,
        -- Correlated subquery: Count of 'Post Closed' history events for this question
        (
            SELECT COUNT(ph.Id)
            FROM PostHistory ph
            WHERE ph.PostId = q.Id
              AND ph.PostHistoryTypeId = 10 -- Post Closed
              AND ph.CreationDate >= q.CreationDate
        ) AS CloseVoteCount,
        -- Window function: Rank questions by score within their creation year and primary tag
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM q.CreationDate), (string_to_array(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><'))[1] ORDER BY q.Score DESC, q.ViewCount DESC) AS RankInYearTag,
        -- Conditional check for code snippets in the question body using LIKE
        (q.Body LIKE '%<pre><code>%' OR q.Body LIKE '%<code>%') AS HasCodeSnippet
    FROM Posts q
    WHERE q.PostTypeId = 1 -- Only questions
      AND q.CreationDate >= '2023-01-01' -- Filter recent questions
      AND q.OwnerUserId IS NOT NULL -- Exclude community-owned or deleted user posts
      AND q.Tags IS NOT NULL AND LENGTH(q.Tags) > 2 -- Ensure tags exist and are properly formatted
),
AnswerPerformance AS (
    -- CTE 3: Analyzes performance of answers, linking them to parent questions, with NULL handling and window functions.
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.CommentCount AS AnswerCommentCount,
        -- Calculation with NULL logic: Calculate age of answer at its last activity date
        EXTRACT(EPOCH FROM (COALESCE(a.LastActivityDate, a.CreationDate) - a.CreationDate)) / (60*60*24) AS AnswerAgeInDays,
        -- Window function: Calculate average score of all answers by the same user to the same parent question
        AVG(a.Score) OVER (PARTITION BY a.OwnerUserId, a.ParentId) AS AvgScoreForUserOnQuestion,
        -- Conditional expression: Determine if this answer was accepted
        CASE WHEN a.Id = q_parent.AcceptedAnswerId THEN TRUE ELSE FALSE END AS IsAcceptedAnswer,
        -- String expression: Check for common gratitude phrases in the answer body
        (a.Body LIKE '%thank you%' OR a.Body LIKE '%Thanks%') AS ContainsGratitude
    FROM Posts a
    INNER JOIN Posts q_parent ON a.ParentId = q_parent.Id
    WHERE a.PostTypeId = 2 -- Only answers
      AND a.OwnerUserId IS NOT NULL
      AND a.CreationDate >= '2023-01-01'
),
CombinedPostEngagement AS (
    -- CTE 4: Combines questions and answers into a single dataset using UNION ALL (set operator).
    SELECT
        p.Id AS EntityId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        'Question' AS EntityType,
        COALESCE(p.Title, LEFT(p.Body, 100)) AS EntityTitleOrExcerpt, -- NULL logic, string expression
        NULL AS ParentQuestionId, -- Questions have no parent
        (string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))[1] AS PrimaryTag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2023-01-01'

    UNION ALL

    SELECT
        a.Id AS EntityId,
        a.OwnerUserId,
        a.PostTypeId,
        a.CreationDate,
        a.Score,
        NULL AS ViewCount, -- Answers do not have a direct 'ViewCount'
        a.CommentCount,
        a.FavoriteCount,
        'Answer' AS EntityType,
        LEFT(a.Body, 100) AS EntityTitleOrExcerpt, -- String expression for answer body excerpt
        a.ParentId AS ParentQuestionId,
        (string_to_array(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><'))[1] AS PrimaryTag -- Get tag from parent question
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 AND a.CreationDate >= '2023-01-01'
)
-- Main Query: Identifies high-impact users based on their questions, answers, badges, and engagement metrics
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserLocation,
    uas.QuestionsCount,
    uas.AnswersCount,
    uas.GoldBadges,
    qpm.QuestionId,
    qpm.Title AS QuestionTitle,
    qpm.QuestionScore,
    qpm.ViewCount AS QuestionViews,
    qpm.PrimaryTag AS QuestionPrimaryTag,
    qpm.RankInYearTag,
    qpm.CloseVoteCount,
    qpm.HasCodeSnippet,
    ap.AnswerId,
    ap.AnswerScore,
    ap.IsAcceptedAnswer,
    ap.AnswerAgeInDays,
    ap.ContainsGratitude,
    cpe.EntityType,
    cpe.EntityTitleOrExcerpt,
    cpe.Score AS EntityScore,
    cpe.ViewCount AS EntityViewCount,
    cpe.CommentCount AS EntityCommentCount,
    -- Window function: Average score of other questions by the same user within the same primary tag
    AVG(CASE WHEN cpe.PostTypeId = 1 THEN cpe.Score ELSE NULL END) OVER (PARTITION BY uas.UserId, qpm.PrimaryTag) AS AvgUserQuestionScoreInTag,
    MAX(ph.CreationDate) AS LastPostHistoryEventDate, -- Most recent post history event by this user
    SUM(CASE WHEN vt_main.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpvotesOnUserPosts,
    SUM(CASE WHEN vt_main.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownvotesOnUserPosts,
    -- Complicated expression with NULL handling and conditional aggregation for a custom user impact score
    CASE
        WHEN uas.QuestionsCount > 0 AND uas.AnswersCount > 0
        THEN (COALESCE(uas.AvgQuestionScore, 0) * 0.7 + COALESCE(uas.AvgAnswerScore, 0) * 0.3) * (uas.GoldBadges + uas.SilverBadges * 0.5 + uas.BronzeBadges * 0.25)
        WHEN uas.QuestionsCount > 0 THEN COALESCE(uas.AvgQuestionScore, 0) * uas.GoldBadges
        WHEN uas.AnswersCount > 0 THEN COALESCE(uas.AvgAnswerScore, 0) * uas.GoldBadges
        ELSE 0
    END AS WeightedUserImpactScore,
    -- Outer Join to PostLinks to find any 'Linked' posts
    pl.LinkTypeId AS RelatedLinkType,
    lt.Name AS RelatedLinkTypeName,
    COUNT(DISTINCT pl.Id) AS NumberOfRelatedPosts,
    -- Correlated subquery: Determine the tag with the highest total score for this specific user's questions
    (
        SELECT tag_name
        FROM (
            SELECT UNNEST(string_to_array(SUBSTRING(p_sub.Tags FROM 2 FOR LENGTH(p_sub.Tags) - 2), '><')) AS tag_name, p_sub.Score
            FROM Posts p_sub
            WHERE p_sub.OwnerUserId = uas.UserId
              AND p_sub.PostTypeId = 1
              AND p_sub.Tags IS NOT NULL AND LENGTH(p_sub.Tags) > 2
        ) AS user_post_tags
        GROUP BY tag_name
        ORDER BY SUM(Score) DESC
        LIMIT 1
    ) AS TopScoringTagForUser
FROM UserActivitySummary uas
INNER JOIN QuestionPerformance qpm ON uas.UserId = qpm.OwnerUserId
LEFT JOIN AnswerPerformance ap ON qpm.QuestionId = ap.QuestionId AND uas.UserId = ap.AnswerOwnerUserId
LEFT JOIN CombinedPostEngagement cpe ON uas.UserId = cpe.OwnerUserId AND qpm.QuestionId = cpe.ParentQuestionId -- Link answers to questions through CombinedPostEngagement
LEFT JOIN PostHistory ph ON uas.UserId = ph.UserId -- Join to PostHistory for any user-related event
LEFT JOIN PostLinks pl ON qpm.QuestionId = pl.PostId AND pl.LinkTypeId = 1 -- Outer Join for 'Linked' posts
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN Votes v_main ON qpm.QuestionId = v_main.PostId -- Outer Join for votes on questions
LEFT JOIN VoteTypes vt_main ON v_main.VoteTypeId = vt_main.Id
WHERE qpm.QuestionScore > 10 AND qpm.ViewCount > 500
  AND (qpm.PrimaryTag LIKE 'sql' OR qpm.PrimaryTag LIKE 'database' OR qpm.PrimaryTag LIKE 'performance') -- Complex predicate: specific tag filtering
  AND qpm.HasCodeSnippet = TRUE -- Only questions containing code snippets
  AND (ap.IsAcceptedAnswer = TRUE OR ap.AnswerId IS NULL) -- Only questions with an accepted answer or no answers yet
  AND uas.GoldBadges > 0 -- Users with at least one gold badge
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.UserLocation, uas.QuestionsCount, uas.AnswersCount,
    uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges, uas.AvgQuestionScore, uas.AvgAnswerScore,
    qpm.QuestionId, qpm.Title, qpm.QuestionScore, qpm.ViewCount, qpm.PrimaryTag, qpm.RankInYearTag,
    qpm.CloseVoteCount, qpm.HasCodeSnippet,
    ap.AnswerId, ap.AnswerScore, ap.IsAcceptedAnswer, ap.AnswerAgeInDays, ap.ContainsGratitude,
    cpe.EntityType, cpe.EntityTitleOrExcerpt, cpe.Score, cpe.ViewCount, cpe.CommentCount,
    pl.LinkTypeId, lt.Name
ORDER BY WeightedUserImpactScore DESC, TotalUpvotesOnUserPosts DESC, LastPostHistoryEventDate DESC
LIMIT 100;
