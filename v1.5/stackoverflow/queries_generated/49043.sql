-- {"query": "49043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2756} 

WITH UserActivityBase AS (
    -- Base user information and general activity dates
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        u.Views AS TotalProfileViews,
        MAX(u.LastAccessDate) AS LastAccessDate,
        MIN(u.CreationDate) AS UserCreationDate
    FROM Users u
    WHERE u.CreationDate >= '2010-01-01' -- Focus on users created after a certain date
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
UserPostStats AS (
    -- Aggregated statistics for user's posts (questions and answers)
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS OwnQuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p.PostTypeId = 2 AND p_q_acc.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersProvided, -- Answers *they* provided that were accepted by others
        SUM(CASE WHEN p.PostTypeId = 1 AND p.ViewCount IS NOT NULL THEN p.ViewCount ELSE 0 END) AS TotalQuestionViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount IS NOT NULL THEN p.FavoriteCount ELSE 0 END) AS TotalQuestionFavoriteCount
    FROM Posts p
    LEFT JOIN Posts p_q_acc ON p.ParentId = p_q_acc.Id AND p_q_acc.PostTypeId = 1 -- Link answers to their parent questions for accepted answers
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= '2015-01-01' -- Activity within a more recent period
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    -- Count of comments made by each user
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentsMade
    FROM Comments c
    WHERE c.UserId IS NOT NULL
      AND c.CreationDate >= '2015-01-01'
    GROUP BY c.UserId
),
UserReceivedCommentStats AS (
    -- Count of comments received on each user's posts
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(c.Id) AS CommentsReceivedOnPosts
    FROM Posts p
    JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= '2015-01-01'
      AND c.CreationDate >= '2015-01-01'
    GROUP BY p.OwnerUserId
),
UserEdits AS (
    -- Count of edits made by each user (excluding initial post creation history)
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalEditsMade
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title, Body, Tags
      AND ph.UserId IS NOT NULL
      AND ph.CreationDate >= '2015-01-01'
    GROUP BY ph.UserId
),
UserBadgeSummary AS (
    -- Summary of badges earned by each user
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= '2015-01-01'
    GROUP BY b.UserId
),
UserTagScore AS (
    -- Calculate average answer score and answer count for users in specific tags
    SELECT
        u.Id AS UserId,
        t.TagName,
        AVG(p_a.Score) AS AvgAnswerScoreInTag,
        COUNT(p_a.Id) AS AnswersInTag
    FROM Users u
    JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2 -- User's answers
    JOIN Posts p_q_parent ON p_a.ParentId = p_q_parent.Id AND p_q_parent.PostTypeId = 1 -- Parent question for tags
    WHERE p_a.CreationDate >= '2020-01-01' -- Focus on recent answers
      AND p_q_parent.CreationDate >= '2020-01-01' -- And recent parent questions
      AND p_q_parent.Tags IS NOT NULL AND LENGTH(p_q_parent.Tags) > 2 -- Ensure tags exist
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p_q_parent.Tags, 2, LENGTH(p_q_parent.Tags) - 2), '><')) AS extracted_tag ON TRUE
    JOIN Tags t ON extracted_tag = t.TagName
    GROUP BY u.Id, t.TagName
    HAVING COUNT(p_a.Id) >= 5 -- Users must have at least 5 answers in the tag
),
RankedTagUsers AS (
    -- Rank users within each tag by average answer score and answer count
    SELECT
        UserId,
        TagName,
        AvgAnswerScoreInTag,
        AnswersInTag,
        ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY AvgAnswerScoreInTag DESC, AnswersInTag DESC) AS rn
    FROM UserTagScore
)
-- Final selection and aggregation to compute a composite engagement score
SELECT
    uab.UserId,
    uab.DisplayName,
    uab.Reputation,
    COALESCE(ups.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(ups.AnswersProvided, 0) AS AnswersProvided,
    COALESCE(ups.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ups.AcceptedAnswersProvided, 0) AS AcceptedAnswersProvided,
    COALESCE(ups.OwnQuestionsWithAcceptedAnswer, 0) AS OwnQuestionsWithAcceptedAnswer,
    COALESCE(ups.TotalQuestionViewCount, 0) AS TotalQuestionViewCount,
    COALESCE(ups.TotalQuestionFavoriteCount, 0) AS TotalQuestionFavoriteCount,
    COALESCE(ue.TotalEditsMade, 0) AS TotalEdits,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ucs.CommentsMade, 0) AS CommentsMade,
    COALESCE(urcs.CommentsReceivedOnPosts, 0) AS CommentsReceivedOnPosts,
    COALESCE(r_tag_sql.AvgAnswerScoreInTag, 0) AS AvgSqlAnswerScore,
    COALESCE(r_tag_python.AvgAnswerScoreInTag, 0) AS AvgPythonAnswerScore,
    COALESCE(r_tag_js.AvgAnswerScoreInTag, 0) AS AvgJSAnswerScore,
    COALESCE(r_tag_java.AvgAnswerScoreInTag, 0) AS AvgJavaAnswerScore,
    COALESCE(r_tag_csharp.AvgAnswerScoreInTag, 0) AS AvgCSharpAnswerScore,
    (
        uab.Reputation * 0.01 + -- Reputation scaled down for comparison
        COALESCE(ups.TotalAnswerScore, 0) * 0.5 +
        COALESCE(ups.AcceptedAnswersProvided, 0) * 5 +
        COALESCE(ups.OwnQuestionsWithAcceptedAnswer, 0) * 2 +
        COALESCE(ups.TotalQuestionViewCount, 0) * 0.001 +
        COALESCE(ups.TotalQuestionFavoriteCount, 0) * 0.1 +
        COALESCE(ue.TotalEditsMade, 0) * 0.1 +
        COALESCE(ubs.GoldBadges, 0) * 10 +
        COALESCE(ubs.SilverBadges, 0) * 2 +
        COALESCE(ubs.BronzeBadges, 0) * 0.5 +
        COALESCE(ucs.CommentsMade, 0) * 0.05 +
        COALESCE(urcs.CommentsReceivedOnPosts, 0) * 0.05 +
        COALESCE(r_tag_sql.AvgAnswerScoreInTag, 0) * 0.1 +
        COALESCE(r_tag_python.AvgAnswerScoreInTag, 0) * 0.1 +
        COALESCE(r_tag_js.AvgAnswerScoreInTag, 0) * 0.1 +
        COALESCE(r_tag_java.AvgAnswerScoreInTag, 0) * 0.1 +
        COALESCE(r_tag_csharp.AvgAnswerScoreInTag, 0) * 0.1
    ) AS CompositeEngagementScore
FROM UserActivityBase uab
LEFT JOIN UserPostStats ups ON uab.UserId = ups.UserId
LEFT JOIN UserEdits ue ON uab.UserId = ue.UserId
LEFT JOIN UserBadgeSummary ubs ON uab.UserId = ubs.UserId
LEFT JOIN UserCommentStats ucs ON uab.UserId = ucs.UserId
LEFT JOIN UserReceivedCommentStats urcs ON uab.UserId = urcs.UserId
-- Join for specific high-volume tags, considering only top N users per tag for further filtering
LEFT JOIN RankedTagUsers r_tag_sql ON uab.UserId = r_tag_sql.UserId AND r_tag_sql.TagName = 'sql' AND r_tag_sql.rn <= 50
LEFT JOIN RankedTagUsers r_tag_python ON uab.UserId = r_tag_python.UserId AND r_tag_python.TagName = 'python' AND r_tag_python.rn <= 50
LEFT JOIN RankedTagUsers r_tag_js ON uab.UserId = r_tag_js.UserId AND r_tag_js.TagName = 'javascript' AND r_tag_js.rn <= 50
LEFT JOIN RankedTagUsers r_tag_java ON uab.UserId = r_tag_java.UserId AND r_tag_java.TagName = 'java' AND r_tag_java.rn <= 50
LEFT JOIN RankedTagUsers r_tag_csharp ON uab.UserId = r_tag_csharp.UserId AND r_tag_csharp.TagName = 'c#' AND r_tag_csharp.rn <= 50
WHERE uab.Reputation > 5000 -- Filter for high-reputation users
  AND COALESCE(ups.AnswersProvided, 0) > 10 -- Only users with a significant number of answers
  AND uab.UserCreationDate < '2022-01-01' -- Exclude very new users to focus on established contributors
ORDER BY CompositeEngagementScore DESC, uab.LastAccessDate DESC
LIMIT 1000;
