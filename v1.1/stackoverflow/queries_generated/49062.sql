-- {"query": "49062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2285} 

WITH UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0 -- Exclude community/deleted users
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade
    FROM Comments c
    WHERE c.UserId IS NOT NULL AND c.UserId > 0
    GROUP BY c.UserId
),
UserVoteEngagement AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCast, -- User cast an upvote
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesCast, -- User cast a downvote
        COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) AS AcceptedAnswersByThisUser, -- User accepted an answer for their question
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesMade -- User favorited a post (bookmark)
    FROM Votes v
    WHERE v.UserId IS NOT NULL AND v.UserId > 0
    GROUP BY v.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserTagExpertise AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS RelevantTagQuestionCount,
        SUM(p.Score) AS RelevantTagQuestionTotalScore,
        SUM(p.ViewCount) AS RelevantTagQuestionTotalViews
    FROM Posts p,
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS extracted_tag
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.Tags IS NOT NULL
      AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
      AND extracted_tag IN ('sql', 'performance', 'database', 'query-optimization', 'indexing', 'optimization', 'postgresql', 'mysql', 'sql-server') -- Specific tags of interest for performance
    GROUP BY p.OwnerUserId
),
UserPostHistoryMetrics AS (
    SELECT
        ph.UserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEditsContributed, -- User edited a post (title, body, tags)
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS TotalReopensContributed, -- User voted to reopen a post
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS TotalClosesContributed -- User voted to close a post
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL AND ph.UserId > 0
    GROUP BY ph.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    EXTRACT(DAY FROM (NOW() - u.CreationDate)) AS DaysOnPlatform,
    COALESCE(ups.TotalQuestions, 0) AS TotalQuestionsAsked,
    COALESCE(ups.TotalAnswers, 0) AS TotalAnswersProvided,
    COALESCE(ups.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(ups.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ups.TotalQuestionViews, 0) AS TotalQuestionViews,
    COALESCE(ucs.TotalCommentsMade, 0) AS TotalCommentsWritten,
    COALESCE(uve.UpVotesCast, 0) AS TotalUpVotesCast,
    COALESCE(uve.DownVotesCast, 0) AS TotalDownVotesCast,
    COALESCE(uve.AcceptedAnswersByThisUser, 0) AS TotalAcceptedAnswersByThisUser,
    COALESCE(uve.FavoritesMade, 0) AS TotalFavoritesMade,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ute.RelevantTagQuestionCount, 0) AS RelevantTagQuestions,
    COALESCE(ute.RelevantTagQuestionTotalScore, 0) AS RelevantTagQuestionsScore,
    COALESCE(ute.RelevantTagQuestionTotalViews, 0) AS RelevantTagQuestionsViews,
    COALESCE(uphm.TotalEditsContributed, 0) AS TotalEditsContributed,
    COALESCE(uphm.TotalReopensContributed, 0) AS TotalReopensContributed,
    COALESCE(uphm.TotalClosesContributed, 0) AS TotalClosesContributed,
    -- Calculate a comprehensive "User Impact Score" combining various contributions
    (
        (COALESCE(u.Reputation, 0) * 0.01) + -- Base reputation contribution
        (COALESCE(ups.TotalQuestionScore, 0) * 0.5) + -- Weighted score from owned questions
        (COALESCE(ups.TotalAnswerScore, 0) * 0.7) + -- Weighted score from owned answers (answers are generally highly valued)
        (COALESCE(ubs.GoldBadges, 0) * 100) + -- Gold badges are very significant indicators of expertise
        (COALESCE(ubs.SilverBadges, 0) * 30) +
        (COALESCE(ubs.BronzeBadges, 0) * 10) +
        (COALESCE(u.UpVotes, 0) * 0.2) - -- UpVotes field from Users table for votes received
        (COALESCE(u.DownVotes, 0) * 0.3) + -- DownVotes field from Users table for votes received (negative impact)
        (COALESCE(ute.RelevantTagQuestionTotalScore, 0) * 0.4) + -- Specific tag expertise score for questions
        (COALESCE(uphm.TotalEditsContributed, 0) * 2) + -- Edits are positive contributions to content quality
        (COALESCE(ucs.TotalCommentsMade, 0) * 0.5) + -- Comments indicate active engagement
        (COALESCE(uve.AcceptedAnswersByThisUser, 0) * 5) + -- Accepting answers shows active question management
        (COALESCE(uve.FavoritesMade, 0) * 0.1) -- Favoriting posts indicates useful curation
    ) AS UserImpactScore,
    RANK() OVER (ORDER BY
        (
            (COALESCE(u.Reputation, 0) * 0.01) +
            (COALESCE(ups.TotalQuestionScore, 0) * 0.5) +
            (COALESCE(ups.TotalAnswerScore, 0) * 0.7) +
            (COALESCE(ubs.GoldBadges, 0) * 100) +
            (COALESCE(ubs.SilverBadges, 0) * 30) +
            (COALESCE(ubs.BronzeBadges, 0) * 10) +
            (COALESCE(u.UpVotes, 0) * 0.2) -
            (COALESCE(u.DownVotes, 0) * 0.3) +
            (COALESCE(ute.RelevantTagQuestionTotalScore, 0) * 0.4) +
            (COALESCE(uphm.TotalEditsContributed, 0) * 2) +
            (COALESCE(ucs.TotalCommentsMade, 0) * 0.5) +
            (COALESCE(uve.AcceptedAnswersByThisUser, 0) * 5) +
            (COALESCE(uve.FavoritesMade, 0) * 0.1)
        ) DESC,
        u.Reputation DESC,
        u.CreationDate ASC
    ) AS OverallRank
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
LEFT JOIN UserVoteEngagement uve ON u.Id = uve.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserTagExpertise ute ON u.Id = ute.UserId
LEFT JOIN UserPostHistoryMetrics uphm ON u.Id = uphm.UserId
WHERE u.Reputation >= 1000 -- Focus on more established users
  AND u.LastAccessDate >= NOW() - INTERVAL '6 months' -- Filter for recently active users
  AND u.DisplayName IS NOT NULL AND u.DisplayName != '' -- Exclude users without a display name
ORDER BY OverallRank
LIMIT 50;
