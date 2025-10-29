-- {"query": "1096.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3888} 
WITH UserBaseStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays,
        COALESCE(u.UpVotes, 0) + COALESCE(u.DownVotes, 0) AS TotalGivenVotes,
        CASE
            WHEN (COALESCE(u.UpVotes, 0) + COALESCE(u.DownVotes, 0)) > 0
            THEN CAST(COALESCE(u.UpVotes, 0) AS NUMERIC) / (COALESCE(u.UpVotes, 0) + COALESCE(u.DownVotes, 0))
            ELSE NULL
        END AS UpvoteRatio,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
PostActivitySummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScoreSum,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsPosted,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersPosted,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersReceived,
        SUM(CASE WHEN p.PostTypeId = 2 AND p_parent.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 15), '; ') FILTER (WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1) AS TopQuestionTagsAggregated
    FROM Posts AS p
    LEFT JOIN Posts AS p_parent ON p.PostTypeId = 2 AND p.ParentId = p_parent.Id
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS t(TagName) ON p.PostTypeId = 1
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
CommentSentimentAnalysis AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN c.Text ILIKE ANY ('%great%', '%good%', '%helpful%', '%thanks%', '%awesome%', '%solved%') THEN 1 ELSE 0 END) AS PositiveCommentsCount,
        SUM(CASE WHEN c.Text ILIKE ANY ('%error%', '%bug%', '%issue%', '%broken%', '%wrong%', '%bad%', '%problem%') THEN 1 ELSE 0 END) AS NegativeCommentsCount,
        AVG(c.Score) AS AvgCommentScore,
        COALESCE(SUM(CASE WHEN c.Text ILIKE ANY ('%great%', '%good%', '%helpful%', '%thanks%', '%awesome%', '%solved%') THEN 1 ELSE 0 END) -
        SUM(CASE WHEN c.Text ILIKE ANY ('%error%', '%bug%', '%issue%', '%broken%', '%wrong%', '%bad%', '%problem%') THEN 1 ELSE 0 END), 0) AS NetSentimentScore
    FROM Comments AS c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostHistoryMetrics AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS PostsWithHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE 0 END) AS RollbackCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS HasClosedPosts,
        MAX(ph.CreationDate) AS LastHistoryActivityDate
    FROM PostHistory AS ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
VoteParticipation AS (
    SELECT
        v.UserId,
        COUNT(v.Id) AS TotalVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotesCast, -- User accepting another's answer
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesCast -- User favoring a post (bookmark)
    FROM Votes AS v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
WikiAndModeratorActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalWikiModPosts,
        SUM(CASE WHEN p.PostTypeId IN (3, 4, 5) THEN p.Score ELSE 0 END) AS TotalWikiScore,
        SUM(CASE WHEN p.PostTypeId = 6 OR p.PostTypeId = 8 THEN p.Score ELSE 0 END) AS TotalModeratorScore,
        MAX(p.LastEditDate) AS LastWikiModEdit
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (3, 4, 5, 6, 8)
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 3 -- At least 3 Wiki/Mod related posts
)
SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.AccountAgeDays,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pas.TotalQuestionsPosted,
    pas.TotalAnswersPosted,
    pas.AcceptedAnswersCount,
    csa.TotalCommentsMade,
    csa.NetSentimentScore,
    phm.EditCount,
    phm.HasClosedPosts,
    vp.UpvotesCast,
    vp.DownvotesCast,
    COALESCE(phm.LastHistoryActivityDate, ubs.LastAccessDate) AS MostRecentActivityDate,
    -- Complex Calculation: Overall Engagement Score for Q&A users
    (ubs.Reputation * 0.15)
    + (COALESCE(pas.AcceptedAnswersCount, 0) * 5)
    + (COALESCE(csa.NetSentimentScore, 0) * 0.8)
    + (COALESCE(phm.EditCount, 0) * 0.3)
    + (COALESCE(pas.AnswerScoreSum, 0) * 0.05) AS OverallEngagementScore,
    -- Window Function: Rank users by Engagement Score within a Reputation bracket
    RANK() OVER (PARTITION BY (ubs.Reputation / 5000) ORDER BY (ubs.Reputation * 0.15) + (COALESCE(pas.AcceptedAnswersCount, 0) * 5) + (COALESCE(csa.NetSentimentScore, 0) * 0.8) + (COALESCE(phm.EditCount, 0) * 0.3) + (COALESCE(pas.AnswerScoreSum, 0) * 0.05) DESC) AS RankInReputationBracket,
    -- Window Function: Percentile rank of UpvoteRatio
    NTILE(10) OVER (ORDER BY ubs.UpvoteRatio DESC NULLS LAST) AS UpvoteRatioPercentile,
    -- Correlated Subquery: Check if user has ever had a question with more than 5 answers
    EXISTS (
        SELECT 1
        FROM Posts p_q_inner
        WHERE p_q_inner.OwnerUserId = ubs.UserId
          AND p_q_inner.PostTypeId = 1
          AND COALESCE(p_q_inner.AnswerCount, 0) > 5
    ) AS HasPopularQuestion,
    -- String expressions and NULL logic
    COALESCE(pas.TopQuestionTagsAggregated, 'No Q&A Tags') AS PrimaryUserTags,
    CASE
        WHEN ubs.Reputation >= 20000 AND ubs.GoldBadges >= 5 AND COALESCE(pas.AcceptedAnswersCount, 0) >= 10 THEN 'Elite Contributor'
        WHEN ubs.Reputation >= 5000 AND ubs.SilverBadges >= 3 AND COALESCE(pas.TotalAnswersPosted, 0) >= 50 THEN 'Seasoned Expert'
        WHEN ubs.Reputation >= 1000 AND COALESCE(pas.TotalQuestionsPosted, 0) >= 10 THEN 'Active Participant'
        ELSE 'Emerging User'
    END AS UserEngagementTier,
    -- Another complex calculation: Average body length for their highly scored questions/answers
    (
        SELECT AVG(LENGTH(p_body.Body))
        FROM Posts p_body
        WHERE p_body.OwnerUserId = ubs.UserId
          AND p_body.PostTypeId IN (1, 2)
          AND p_body.Score > 10
    ) AS AvgGoodPostContentLength,
    -- Correlated Subquery: Count of posts linked as duplicates by this user (if OwnerUserId is on the PostId side of PostLinks)
    (
        SELECT COUNT(DISTINCT pl_dup.RelatedPostId)
        FROM Posts p_owned
        JOIN PostLinks pl_dup ON p_owned.Id = pl_dup.PostId
        WHERE p_owned.OwnerUserId = ubs.UserId
          AND pl_dup.LinkTypeId = 3 -- Duplicate link type
    ) AS DuplicatesLinkedBySelf,
    'Q&A Contributor' AS ProfileType
FROM UserBaseStats AS ubs
LEFT JOIN PostActivitySummary AS pas ON ubs.UserId = pas.UserId
LEFT JOIN CommentSentimentAnalysis AS csa ON ubs.UserId = csa.UserId
LEFT JOIN PostHistoryMetrics AS phm ON ubs.UserId = phm.UserId
LEFT JOIN VoteParticipation AS vp ON ubs.UserId = vp.UserId
WHERE ubs.Reputation > 500
  AND ubs.LastAccessDate >= '2023-01-01'
  AND ubs.DisplayName IS NOT NULL
  -- Ensure not just a user who only answers and never asks
  AND NOT EXISTS (
      SELECT 1 FROM Posts p_only_answers
      WHERE p_only_answers.OwnerUserId = ubs.UserId
        AND p_only_answers.PostTypeId = 2
      EXCEPT
      SELECT 1 FROM Posts p_has_questions
      WHERE p_has_questions.OwnerUserId = ubs.UserId
        AND p_has_questions.PostTypeId = 1
  )

UNION ALL

-- Secondary result set: Dedicated Wiki & Moderator Contributors
SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.AccountAgeDays,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    NULL AS TotalQuestionsPosted, -- Q&A specific metric, null for this segment
    NULL AS TotalAnswersPosted,
    NULL AS AcceptedAnswersCount,
    NULL AS TotalCommentsMade,
    NULL AS NetSentimentScore,
    phm.EditCount, -- History metrics are still relevant
    phm.HasClosedPosts,
    vp.UpvotesCast, -- Voting activity is still relevant
    vp.DownvotesCast,
    COALESCE(wm.LastWikiModEdit, phm.LastHistoryActivityDate, ubs.LastAccessDate) AS MostRecentActivityDate,
    -- Different Engagement Score for Wiki/Mod users
    (ubs.Reputation * 0.1)
    + (COALESCE(wm.TotalWikiScore, 0) * 1.5)
    + (COALESCE(wm.TotalModeratorScore, 0) * 2.0)
    + (COALESCE(phm.EditCount, 0) * 0.5) AS OverallEngagementScore,
    -- Window Function: Rank based on Wiki/Mod score
    RANK() OVER (ORDER BY (COALESCE(wm.TotalWikiScore, 0) * 1.5) + (COALESCE(wm.TotalModeratorScore, 0) * 2.0) DESC, ubs.Reputation DESC) AS RankInReputationBracket,
    NTILE(10) OVER (ORDER BY ubs.UpvoteRatio DESC NULLS LAST) AS UpvoteRatioPercentile, -- Still use UpvoteRatio percentile
    -- Correlated Subquery: Check if user has authored a TagWiki or TagWikiExcerpt
    EXISTS (
        SELECT 1
        FROM Posts p_wiki_inner
        WHERE p_wiki_inner.OwnerUserId = ubs.UserId
          AND p_wiki_inner.PostTypeId IN (4, 5)
          AND p_wiki_inner.Score > 0
    ) AS HasPopularQuestion, -- Reusing column name, but meaning "Has Popular Wiki Content"
    COALESCE(STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 15), '; ') FILTER (WHERE p_tag.Tags IS NOT NULL), 'No Wiki Tags') AS PrimaryUserTags,
    CASE
        WHEN COALESCE(wm.TotalModeratorScore, 0) > 0 AND ubs.Reputation >= 10000 THEN 'Moderator/Admin'
        WHEN COALESCE(wm.TotalWikiScore, 0) >= 100 AND ubs.GoldBadges >= 1 THEN 'Wiki Architect'
        WHEN COALESCE(wm.TotalWikiModPosts, 0) >= 5 THEN 'Wiki Contributor'
        ELSE 'Casual Helper'
    END AS UserEngagementTier,
    (
        SELECT AVG(LENGTH(p_body.Body))
        FROM Posts p_body
        WHERE p_body.OwnerUserId = ubs.UserId
          AND p_body.PostTypeId IN (3, 4, 5, 6, 8)
          AND p_body.Score > 5
    ) AS AvgGoodPostContentLength,
    NULL AS DuplicatesLinkedBySelf, -- Q&A specific metric, null for this segment
    'Wiki/Mod Contributor' AS ProfileType
FROM UserBaseStats AS ubs
JOIN WikiAndModeratorActivity AS wm ON ubs.UserId = wm.UserId -- INNER JOIN, only show users with significant wiki/mod activity
LEFT JOIN PostHistoryMetrics AS phm ON ubs.UserId = phm.UserId
LEFT JOIN VoteParticipation AS vp ON ubs.UserId = vp.UserId
LEFT JOIN Posts AS p_tag ON ubs.UserId = p_tag.OwnerUserId AND p_tag.PostTypeId IN (4, 5)
LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p_tag.Tags FROM 2 FOR LENGTH(p_tag.Tags) - 2), '><')) AS t(TagName) ON TRUE
WHERE ubs.Reputation > 2000
  AND ubs.DisplayName IS NOT NULL
GROUP BY ubs.UserId, ubs.DisplayName, ubs.Reputation, ubs.AccountAgeDays, ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, phm.EditCount, phm.HasClosedPosts, vp.UpvotesCast, vp.DownvotesCast, wm.LastWikiModEdit, phm.LastHistoryActivityDate, ubs.LastAccessDate, wm.TotalWikiScore, wm.TotalModeratorScore, wm.TotalWikiModPosts, ubs.UpvoteRatio
ORDER BY OverallEngagementScore DESC, Reputation DESC
LIMIT 200;