-- {"query": "49058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1972} 

WITH UserQuestionStats AS (
    -- Aggregate initial statistics for questions owned by users, including vote counts
    SELECT
        p.OwnerUserId,
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.CommentCount,
        p.FavoriteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Posts p
    JOIN VoteTypes vt ON vt.Id IN (2, 3) -- Only join for upvotes/downvotes
    JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = vt.Id
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= '2020-01-01' -- Filter for more recent, active questions
    GROUP BY p.OwnerUserId, p.Id, p.Title, p.ViewCount, p.Score, p.CreationDate, p.Tags, p.CommentCount, p.FavoriteCount
),
RankedQuestions AS (
    -- Calculate a composite engagement score for each question and rank them per user
    SELECT
        OwnerUserId,
        QuestionId,
        Title,
        ViewCount,
        Score,
        CreationDate,
        Tags,
        CommentCount,
        FavoriteCount,
        UpvoteCount,
        DownvoteCount,
        (ViewCount * 0.01 + Score * 2 + UpvoteCount * 3 + FavoriteCount * 5 + CommentCount * 1.5) AS CompositeEngagementScore,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY (ViewCount * 0.01 + Score * 2 + UpvoteCount * 3 + FavoriteCount * 5 + CommentCount * 1.5) DESC, CreationDate DESC) AS rn
    FROM UserQuestionStats
),
TopUserQuestions AS (
    -- Select the top N (e.g., 5) most engaging questions for each influential user
    SELECT
        rq.OwnerUserId,
        rq.QuestionId,
        rq.Title,
        rq.ViewCount,
        rq.Score,
        rq.CreationDate,
        rq.Tags,
        rq.CommentCount,
        rq.FavoriteCount,
        rq.UpvoteCount,
        rq.DownvoteCount,
        rq.CompositeEngagementScore
    FROM RankedQuestions rq
    WHERE rq.rn <= 5 -- Limit to top 5 questions per user
),
UserOverallStats AS (
    -- Aggregate comprehensive statistics for each user, including total questions, answers, accepted answers,
    -- comments, badge counts, and post history edits.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p_q.Id) AS TotalQuestionsAsked,
        SUM(p_q.Score) AS TotalQuestionScore,
        SUM(p_q.ViewCount) AS TotalQuestionViews,
        COUNT(DISTINCT p_a.Id) AS TotalAnswersProvided,
        SUM(CASE WHEN p_q_accept.AcceptedAnswerId = p_a.Id THEN 1 ELSE 0 END) AS TotalAcceptedAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT ph_edit.Id) AS TotalPostHistoryEdits
    FROM Users u
    LEFT JOIN Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = 1
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2
    LEFT JOIN Posts p_q_accept ON p_a.ParentId = p_q_accept.Id AND p_q_accept.PostTypeId = 1 -- Link answers to parent questions
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph_edit ON u.Id = ph_edit.UserId AND ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
    HAVING COUNT(DISTINCT p_q.Id) >= 10 -- Minimum threshold for questions
       AND SUM(CASE WHEN p_q_accept.AcceptedAnswerId = p_a.Id THEN 1 ELSE 0 END) >= 5 -- Minimum threshold for accepted answers
       AND COUNT(DISTINCT ph_edit.Id) >= 20 -- Minimum threshold for edit activity
       AND COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) >= 1 -- At least one gold badge
       AND u.Reputation >= 5000 -- High reputation threshold
)
-- Final selection combining user overall stats with their top questions and adding correlated post history details
SELECT
    uos.UserId,
    uos.DisplayName,
    uos.Reputation,
    uos.Views,
    uos.TotalQuestionsAsked,
    uos.TotalQuestionScore,
    uos.TotalQuestionViews,
    uos.TotalAnswersProvided,
    uos.TotalAcceptedAnswers,
    uos.TotalCommentsMade,
    uos.GoldBadges,
    uos.SilverBadges,
    uos.BronzeBadges,
    uos.TotalPostHistoryEdits,
    tq.QuestionId,
    tq.Title AS TopQuestionTitle,
    tq.CreationDate AS TopQuestionCreationDate,
    tq.ViewCount AS TopQuestionViewCount,
    tq.Score AS TopQuestionScore,
    tq.UpvoteCount AS TopQuestionUpvoteCount,
    tq.FavoriteCount AS TopQuestionFavoriteCount,
    tq.CompositeEngagementScore AS TopQuestionEngagementScore,
    tq.Tags AS TopQuestionRawTags,
    -- Extract and aggregate significant tags from the top question
    (
        SELECT STRING_AGG(t.TagName, ', ' ORDER BY t.Count DESC)
        FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(tq.Tags, 2, LENGTH(tq.Tags) - 2), '><')) AS q_tag_name
        JOIN Tags t ON t.TagName = q_tag_name
        WHERE t.Count > 1000 -- Filter for tags that are frequently used
        LIMIT 3 -- Get up to 3 most significant tags
    ) AS TopQuestionSignificantTags,
    -- Count distinct edit history entries for the top question
    (
        SELECT COUNT(DISTINCT ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = tq.QuestionId
          AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    ) AS TopQuestionEditCount,
    -- Count close/reopen history entries for the top question
    (
        SELECT COUNT(DISTINCT ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = tq.QuestionId
          AND ph.PostHistoryTypeId IN (10, 11) -- Post Closed, Post Reopened
    ) AS TopQuestionCloseReopenCount,
    -- Get the creation date of the initial body for the top question
    (
        SELECT MIN(ph.CreationDate)
        FROM PostHistory ph
        WHERE ph.PostId = tq.QuestionId AND ph.PostHistoryTypeId = 2 -- Initial Body
    ) AS TopQuestionFirstBodyDate,
    -- Get the date of the last body edit for the top question
    (
        SELECT MAX(ph.CreationDate)
        FROM PostHistory ph
        WHERE ph.PostId = tq.QuestionId AND ph.PostHistoryTypeId = 5 -- Edit Body
    ) AS TopQuestionLastBodyEditDate
FROM UserOverallStats uos
JOIN TopUserQuestions tq ON uos.UserId = tq.OwnerUserId
ORDER BY
    uos.Reputation DESC,
    uos.GoldBadges DESC,
    uos.TotalAcceptedAnswers DESC,
    tq.CompositeEngagementScore DESC
LIMIT 100;
