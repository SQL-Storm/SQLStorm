-- {"query": "1560.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2610} 

WITH UserActivitySummary AS (
    -- Summarizes user post and comment activity, reputation metrics
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotesGiven,
        U.DownVotes AS UserTotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScoreReceived,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / 86400 AS AccountAgeDays
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
),
PostEditHistory AS (
    -- Tracks post editing and closure events, calculating time differences and aggregating close reasons
    SELECT
        PH.PostId,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (1, 2, 3) THEN PH.CreationDate END) AS InitialCreationDate, -- Initial Title, Body, Tags
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,       -- Edit Title, Body, Tags
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS LastEditDate,        -- Last Edit
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS CloseDate,                   -- Post Closed
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS ReopenDate,                  -- Post Reopened
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.CreationDate END) AS DeletionDate,                -- Post Deleted
        STRING_AGG(DISTINCT CRT.Name, ', ') FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL) AS AllCloseReasons,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEditCount
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND PH.Comment ~ '^[0-9]+$' AND PH.Comment::smallint = CRT.Id
    GROUP BY PH.PostId
),
PostTagAnalysis AS (
    -- Extracts individual tags from posts and filters by PostTypeId
    SELECT
        P.Id AS PostId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.ViewCount AS PostViewCount,
        P.Score AS PostScore,
        P.AnswerCount,
        P.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(TRIM(P.Tags)) > 2
),
RankedBadges AS (
    -- Ranks users by the number of gold badges they possess, then silver, then bronze
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(CASE WHEN B.Class = 1 THEN 1 END) DESC, COUNT(B.Id) DESC, MAX(B.Date) DESC) AS BadgeRank
    FROM Badges B
    GROUP BY B.UserId
),
TopLinkedPosts AS (
    -- Identifies posts that are frequently linked or are duplicates
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS OutgoingLinks,
        COUNT(DISTINCT PL_rev.PostId) AS IncomingLinks,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateLinksOut,
        COUNT(DISTINCT CASE WHEN PL_rev.LinkTypeId = 3 THEN PL_rev.PostId END) AS DuplicateLinksIn
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN PostLinks PL_rev ON P.Id = PL_rev.RelatedPostId
    GROUP BY P.Id
    HAVING COUNT(DISTINCT PL.RelatedPostId) + COUNT(DISTINCT PL_rev.PostId) > 0
)
-- Main query combining all the CTEs and performing final aggregations/joins
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserProfileViews,
    UAS.TotalPostsCreated,
    UAS.QuestionsAsked,
    UAS.AnswersProvided,
    UAS.TotalCommentsMade,
    UAS.TotalPostScoreReceived,
    UAS.TotalCommentScoreReceived,
    UAS.AccountAgeDays,
    RB.GoldBadges,
    RB.SilverBadges,
    RB.BronzeBadges,
    RB.BadgeRank,
    SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
    AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScore,
    MIN(CASE WHEN P.PostTypeId = 1 AND PEH.FirstEditDate IS NOT NULL THEN EXTRACT(EPOCH FROM (PEH.FirstEditDate - PEH.InitialCreationDate)) / 3600 END) AS MinHoursToFirstQuestionEdit,
    MAX(PEH.TotalEditCount) AS MaxPostEditCount,
    STRING_AGG(DISTINCT PTA.TagName, ', ') FILTER (WHERE PTA.TagName IS NOT NULL) AS AssociatedTags,
    SUM(COALESCE(TLP.OutgoingLinks, 0)) AS TotalOutgoingLinks,
    SUM(COALESCE(TLP.IncomingLinks, 0)) AS TotalIncomingLinks,
    SUM(COALESCE(TLP.DuplicateLinksIn, 0)) AS TotalDuplicateLinksReceived,
    AVG(CASE WHEN P.PostTypeId = 1 THEN COALESCE(P.AnswerCount, 0) ELSE NULL END) AS AvgAnswersPerQuestion,
    COUNT(DISTINCT P.Id) FILTER (WHERE P.ClosedDate IS NOT NULL) AS TotalClosedPosts,
    COUNT(DISTINCT P.AcceptedAnswerId) FILTER (WHERE P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswersCount,
    -- Correlated Subquery: Find the creation date of the accepted answer for the user's highest scored question
    (
        SELECT MIN(A.CreationDate)
        FROM Posts Q_inner
        JOIN Posts A ON Q_inner.AcceptedAnswerId = A.Id
        WHERE Q_inner.OwnerUserId = UAS.UserId
          AND Q_inner.PostTypeId = 1
          AND A.PostTypeId = 2
          AND Q_inner.Score = (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = UAS.UserId AND PostTypeId = 1 AND AcceptedAnswerId IS NOT NULL)
          AND Q_inner.AcceptedAnswerId IS NOT NULL
    ) AS HighestScoreQuestionAcceptedAnswerDate,
    -- Window Function: Rank users by their total post score within their account age bracket (e.g., every 90 days)
    RANK() OVER (PARTITION BY FLOOR(UAS.AccountAgeDays / 90) ORDER BY UAS.TotalPostScoreReceived DESC) AS RankByScoreInAgeBracket,
    -- Case Expression with NULL logic and string operation
    CASE
        WHEN UAS.Reputation > 50000 AND RB.GoldBadges >= 5 THEN 'Highly Influential Top Contributor'
        WHEN UAS.Reputation > 10000 AND RB.SilverBadges >= 10 AND UAS.TotalPostsCreated > 100 THEN 'Experienced Power User'
        WHEN UAS.TotalCommentsMade > 500 AND UAS.TotalPostScoreReceived IS NOT NULL AND UAS.TotalPostScoreReceived > 0 THEN 'Active Engager'
        WHEN UAS.DisplayName LIKE '%Moderator%' THEN 'Community Moderator'
        ELSE COALESCE(UAS.DisplayName, 'Anonymous') || ' (Regular Contributor)'
    END AS UserInfluenceCategory
FROM UserActivitySummary UAS
LEFT JOIN Posts P ON UAS.UserId = P.OwnerUserId
LEFT JOIN PostEditHistory PEH ON P.Id = PEH.PostId
LEFT JOIN PostTagAnalysis PTA ON P.Id = PTA.PostId
LEFT JOIN RankedBadges RB ON UAS.UserId = RB.UserId
LEFT JOIN TopLinkedPosts TLP ON P.Id = TLP.PostId
WHERE UAS.Reputation > 1000
  AND (UAS.QuestionsAsked > 0 OR UAS.AnswersProvided > 0)
  AND UAS.AccountAgeDays > 30 -- Filter out very new users
  AND NOT EXISTS (
        SELECT 1
        FROM Comments CM
        WHERE CM.UserId = UAS.UserId
          AND (CM.Text ILIKE '%spam%' OR CM.Text ILIKE '%scam%') -- Case-insensitive string matching
          AND CM.CreationDate > NOW() - INTERVAL '1 year'
      ) -- Exclude users with recent "spam" comments (demonstrates NOT EXISTS, string ops)
  AND (
        (P.PostTypeId = 1 AND P.ViewCount > 500 AND P.Score > 5) OR
        (P.PostTypeId = 2 AND P.ParentId IS NOT NULL AND P.Score > 10 AND P.Body LIKE '%<code>%</code>%') -- Answer with code block (string pattern)
      ) IS NOT FALSE -- NULL logic: treat NULL from LEFT JOIN as false.
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserProfileViews, UAS.TotalPostsCreated,
    UAS.QuestionsAsked, UAS.AnswersProvided, UAS.TotalCommentsMade, UAS.TotalPostScoreReceived,
    UAS.TotalCommentScoreReceived, UAS.AccountAgeDays, RB.GoldBadges, RB.SilverBadges,
    RB.BronzeBadges, RB.BadgeRank
HAVING
    COUNT(DISTINCT P.Id) > 5 -- At least 5 relevant posts
    AND SUM(COALESCE(TLP.IncomingLinks, 0)) >= 1 -- Has at least one incoming link
ORDER BY
    UAS.Reputation DESC, RB.GoldBadges DESC, UAS.TotalPostScoreReceived DESC
LIMIT 100;
