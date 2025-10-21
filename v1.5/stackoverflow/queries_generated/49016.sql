-- {"query": "49016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2331} 

WITH UserQuestionStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
        SUM(p.Score) AS TotalQuestionScore,
        SUM(p.ViewCount) AS TotalQuestionViews,
        MAX(p.CreationDate) AS LatestQuestionDate,
        MIN(p.CreationDate) AS EarliestQuestionDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserAnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalAnswersPosted,
        SUM(p.Score) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LatestAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ReceivedUpVotesOnPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ReceivedDownVotesOnPosts,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS ReceivedFavoriteCountOnPosts
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserTopQuestions AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS TopQuestionId,
        p.Title AS TopQuestionTitle,
        p.Score AS TopQuestionScore,
        p.ViewCount AS TopQuestionViewCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserControversialAnswers AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS ControversialAnswerId,
        p.ParentId AS QuestionForAnswerId,
        p.Score AS ControversialAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AnswerUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AnswerDownvotes,
        RANK() OVER(
            PARTITION BY p.OwnerUserId
            ORDER BY (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) + SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) DESC, -- Total votes
                     ABS(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) ASC, -- Closer to equal up/down
                     p.Score ASC -- Lower net score for controversy
        ) AS rnk
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.Id, p.ParentId, p.Score
    HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) >= 5 AND SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) >= 5
),
UserTagContributions AS (
    SELECT
        p.OwnerUserId AS UserId,
        t.TagName,
        COUNT(p.Id) AS PostsInTagCount,
        SUM(p.Score) AS TagPostsScore,
        RANK() OVER(PARTITION BY p.OwnerUserId ORDER BY COUNT(p.Id) DESC, SUM(p.Score) DESC) AS TagRank
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY p.OwnerUserId, t.TagName
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views AS UserProfileViews,
    COALESCE(uqs.TotalQuestionsAsked, 0) AS TotalQuestionsAsked,
    COALESCE(uqs.QuestionsWithAcceptedAnswer, 0) AS QuestionsWithAcceptedAnswer,
    COALESCE(uqs.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(uas.TotalAnswersPosted, 0) AS TotalAnswersPosted,
    COALESCE(uas.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(uvs.ReceivedUpVotesOnPosts, 0) AS ReceivedUpVotesOnPosts,
    COALESCE(uvs.ReceivedDownVotesOnPosts, 0) AS ReceivedDownVotesOnPosts,
    COALESCE(uvs.ReceivedFavoriteCountOnPosts, 0) AS ReceivedFavoriteCountOnPosts,
    u.UpVotes AS UserTotalUpVotesGiven,
    u.DownVotes AS UserTotalDownVotesGiven,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    tq.TopQuestionTitle,
    tq.TopQuestionScore,
    tq.TopQuestionViewCount,
    ca.ControversialAnswerId,
    ca.ControversialAnswerScore,
    ca.AnswerUpvotes,
    ca.AnswerDownvotes,
    q_for_ca.Title AS QuestionForControversialAnswerTitle,
    (u.Reputation * 0.4 +
     COALESCE(uqs.TotalQuestionScore, 0) * 0.1 +
     COALESCE(uqs.QuestionsWithAcceptedAnswer, 0) * 5 +
     COALESCE(uas.TotalAnswerScore, 0) * 0.15 +
     COALESCE(uvs.ReceivedUpVotesOnPosts, 0) * 0.05 +
     COALESCE(uvs.ReceivedFavoriteCountOnPosts, 0) * 2 +
     COALESCE(ubs.GoldBadges, 0) * 50 +
     COALESCE(ubs.SilverBadges, 0) * 10 +
     COALESCE(ubs.BronzeBadges, 0) * 1 +
     COALESCE(u.Views, 0) * 0.01) AS InfluenceScore,
    string_agg(DISTINCT utc.TagName, ', ') FILTER (WHERE utc.TagRank <= 3) AS Top3ContributingTags,
    MAX(GREATEST(COALESCE(uqs.LatestQuestionDate, '1900-01-01'), COALESCE(uas.LatestAnswerDate, '1900-01-01'), u.LastAccessDate)) AS LatestActivityDate
FROM Users u
LEFT JOIN UserQuestionStats uqs ON u.Id = uqs.UserId
LEFT JOIN UserAnswerStats uas ON u.Id = uas.UserId
LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserTopQuestions tq ON u.Id = tq.UserId AND tq.rn = 1
LEFT JOIN UserControversialAnswers ca ON u.Id = ca.UserId AND ca.rnk = 1
LEFT JOIN Posts q_for_ca ON ca.QuestionForAnswerId = q_for_ca.Id
LEFT JOIN UserTagContributions utc ON u.Id = utc.UserId
WHERE
    u.Reputation > 5000 AND -- Filter for reasonably active and reputable users
    COALESCE(uqs.TotalQuestionsAsked, 0) >= 5 AND -- Must have asked at least 5 questions
    COALESCE(uas.TotalAnswersPosted, 0) >= 10 AND -- Must have posted at least 10 answers
    u.LastAccessDate > NOW() - INTERVAL '1 year' -- Active within the last year
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes,
    uqs.TotalQuestionsAsked, uqs.QuestionsWithAcceptedAnswer, uqs.TotalQuestionScore,
    uas.TotalAnswersPosted, uas.TotalAnswerScore,
    uvs.ReceivedUpVotesOnPosts, uvs.ReceivedDownVotesOnPosts, uvs.ReceivedFavoriteCountOnPosts,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
    tq.TopQuestionTitle, tq.TopQuestionScore, tq.TopQuestionViewCount,
    ca.ControversialAnswerId, ca.ControversialAnswerScore, ca.AnswerUpvotes, ca.AnswerDownvotes,
    q_for_ca.Title
ORDER BY InfluenceScore DESC, u.Reputation DESC, LatestActivityDate DESC
LIMIT 100;
