-- {"query": "49057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1669} 

WITH RecentActiveUsers AS (
    -- Identify users who have been active in the last 5 years, have decent reputation,
    -- and possess at least one Gold badge, indicating significant contribution.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesCount, -- Count of Gold badges
        COUNT(DISTINCT ph.Id) AS PostHistoryContributions, -- Number of post history events initiated by the user
        MAX(u.LastAccessDate) AS LastSeen
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
      AND u.Reputation >= 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) >= 1 -- Ensure at least one Gold badge
),
TopQuestionTags AS (
    -- Dynamically identify the top 5 most frequent tags from questions created in the last 2 years.
    -- This involves parsing the 'Tags' string, which can be computationally intensive.
    SELECT TagName FROM (
        SELECT
            UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
            COUNT(p.Id) AS TagCount
        FROM Posts p
        WHERE p.PostTypeId = 1 -- Focus on questions
          AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2 years')
          AND p.Tags IS NOT NULL
          AND length(p.Tags) > 2 -- Exclude empty or malformed tag strings
        GROUP BY 1
        ORDER BY TagCount DESC
        LIMIT 5
    ) AS TopTagsSubquery
),
UserPostMetrics AS (
    -- Aggregate detailed post-related metrics for identified active users over the last 3 years,
    -- distinguishing between questions and answers.
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.ParentId IN (SELECT Id FROM Posts WHERE AcceptedAnswerId = p.Id) THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT UserId FROM RecentActiveUsers)
      AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 years')
    GROUP BY p.OwnerUserId
),
QuestionPerformance AS (
    -- Analyze the performance of recent questions (last 2 years) that are related to the top tags,
    -- calculating scores, view counts, comment counts, linked posts, and upvote/downvote ratios.
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViews,
        p.CommentCount AS QuestionCommentCount,
        p.OwnerUserId AS QuestionOwnerId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT v_up.Id) AS UpvoteCount,
        COUNT(DISTINCT v_down.Id) AS DownvoteCount,
        (CAST(COUNT(DISTINCT v_up.Id) AS NUMERIC) / NULLIF(COUNT(DISTINCT v_up.Id) + COUNT(DISTINCT v_down.Id), 0)) AS UpvoteRatio
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1 -- Links to other posts
    LEFT JOIN Votes v_up ON p.Id = v_up.PostId AND v_up.VoteTypeId = 2 -- Upvotes
    LEFT JOIN Votes v_down ON p.Id = v_down.PostId AND v_down.VoteTypeId = 3 -- Downvotes
    WHERE p.PostTypeId = 1 -- Only consider questions
      AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2 years')
      AND EXISTS ( -- Ensure the question is associated with one of the identified top tags
          SELECT 1
          FROM TopQuestionTags tqt
          WHERE p.Tags LIKE '%' || tqt.TagName || '%'
      )
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CommentCount, p.OwnerUserId
    HAVING COUNT(DISTINCT v_up.Id) > 5 -- At least 5 upvotes
      AND COUNT(DISTINCT v_down.Id) < COUNT(DISTINCT v_up.Id) -- More upvotes than downvotes
)
-- Final selection: Combine user activity, post metrics, and question performance.
-- Rank users based on a composite score reflecting reputation, badge achievements, post scores, and historical impact.
-- Also rank the top questions for each user to highlight their best contributions.
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.GoldBadgesCount,
    rau.PostHistoryContributions,
    upm.TotalQuestionsAsked,
    upm.TotalQuestionViews,
    upm.TotalAnswersGiven,
    upm.TotalAnswerScore,
    upm.QuestionsWithAcceptedAnswers,
    upm.AcceptedAnswersCount,
    RANK() OVER ( -- Overall ranking of users based on their aggregated performance
        ORDER BY
            rau.Reputation DESC,
            rau.GoldBadgesCount DESC,
            upm.TotalAnswerScore DESC,
            upm.TotalQuestionViews DESC,
            rau.PostHistoryContributions DESC
    ) AS OverallUserRank,
    qp.QuestionId,
    qp.QuestionTitle,
    qp.QuestionScore,
    qp.QuestionViews,
    qp.QuestionCommentCount,
    qp.LinkedPostCount,
    qp.UpvoteCount,
    qp.DownvoteCount,
    qp.UpvoteRatio,
    ROW_NUMBER() OVER ( -- Ranking of questions within each user's contributions
        PARTITION BY rau.UserId
        ORDER BY qp.QuestionScore DESC, qp.QuestionViews DESC, qp.QuestionCommentCount DESC
    ) AS UserQuestionRank
FROM RecentActiveUsers rau
JOIN UserPostMetrics upm ON rau.UserId = upm.UserId
LEFT JOIN QuestionPerformance qp ON rau.UserId = qp.QuestionOwnerId
WHERE rau.LastSeen >= (CURRENT_TIMESTAMP - INTERVAL '1 year') -- Ensure users have been active recently
  AND qp.QuestionId IS NOT NULL -- Only include users who have top-performing questions
ORDER BY OverallUserRank ASC, UserQuestionRank ASC
LIMIT 100;
