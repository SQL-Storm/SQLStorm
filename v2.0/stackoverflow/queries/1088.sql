-- {"query": "1088.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4057}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        COALESCE(MAX(P.LastActivityDate), MAX(U.LastAccessDate)) AS LastKnownActivity,
        COUNT(DISTINCT B.Id) AS DistinctBadgesCount,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN P.AcceptedAnswerId = A.Id AND A.OwnerUserId = U.Id THEN 1 ELSE 0 END) AS SelfAcceptedAnswers,
        SUM(U.UpVotes) AS TotalUpVotes,
        SUM(U.DownVotes) AS TotalDownVotes
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts A ON P.AcceptedAnswerId = A.Id
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
),
PostEditTimeline AS (
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS EditDate,
        PH.PostHistoryTypeId,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId, PH.UserId ORDER BY PH.CreationDate) AS PreviousEditDate,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn_latest_edit_per_post,
        ABS(LENGTH(PH.Text) - LENGTH(LAG(PH.Text, 1, PH.Text) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) AS TextLengthChange,
        PH.Text AS EditedTextContent
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)
),
HighImpactPosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.OwnerUserId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        COALESCE(P.ClosedDate, TIMESTAMP '9999-12-31 00:00:00') AS ClosedDateSentinel,
        P.Tags,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = P.Id AND C.Score IS NOT NULL) AS AverageCommentScore,
        CASE
            WHEN P.PostTypeId = 1 AND P.ViewCount > 15000 AND P.AnswerCount >= 7 AND COALESCE(P.Score, 0) >= 15 THEN 'HighTrafficQuestion'
            WHEN P.PostTypeId = 2 AND P.ParentId IS NOT NULL AND COALESCE(P.Score, 0) >= 25 AND P.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years' THEN 'HighScoreRecentAnswer'
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL AND COALESCE(P.FavoriteCount, 0) > 10 THEN 'AcceptedFavoriteQuestion'
            ELSE 'OtherImpact'
        END AS ImpactCategory,
        (SELECT COUNT(DISTINCT PL.RelatedPostId) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS OutgoingLinkedPostCount,
        (SELECT COUNT(DISTINCT PL.PostId) FROM PostLinks PL WHERE PL.RelatedPostId = P.Id AND PL.LinkTypeId = 1) AS IncomingLinkedPostCount,
        (SELECT COUNT(DISTINCT PL.RelatedPostId) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS DuplicateLinkedPostCount
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
    AND P.OwnerUserId IS NOT NULL
    AND P.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5 years'
),
FoundationalReferencedPosts AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate,
        P.ViewCount,
        P.Score,
        P.AnswerCount,
        P.CommentCount,
        COUNT(PL.PostId) AS IncomingLinkCount
    FROM Posts P
    INNER JOIN PostLinks PL ON P.Id = PL.RelatedPostId AND PL.LinkTypeId = 1
    WHERE P.PostTypeId = 1
    AND P.CreationDate < TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 years'
    GROUP BY P.Id, P.OwnerUserId, P.Title, P.CreationDate, P.ViewCount, P.Score, P.AnswerCount, P.CommentCount
    HAVING COUNT(PL.PostId) >= 5
    AND COALESCE(P.Score, 0) < 15
),
UsersWithHighEngagementAndLowDownvotes AS (
    SELECT U.Id AS UserId
    FROM Users U
    WHERE U.Reputation > 2000 AND U.DownVotes < 50
)

SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.QuestionsPosted,
    UAS.AnswersPosted,
    UAS.TotalPostScore,
    UAS.LastKnownActivity,
    UAS.DistinctBadgesCount,
    UAS.QuestionsWithAcceptedAnswer,
    UAS.SelfAcceptedAnswers,
    HIP.PostId,
    HIP.Title AS PostTitle,
    HIP.PostScore,
    HIP.ViewCount,
    HIP.ImpactCategory,
    HIP.AverageCommentScore,
    ROUND(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - UAS.UserCreationDate)) / 86400, 2) AS UserAgeInDays,
    ROUND(EXTRACT(EPOCH FROM (HIP.LastActivityDate - HIP.PostCreationDate)) / 3600, 2) AS PostActivityDurationHours,
    RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.TotalPostScore DESC, HIP.IncomingLinkedPostCount DESC) AS GlobalInfluenceRank,
    EXISTS (
        SELECT 1
        FROM Badges B
        INNER JOIN Tags T ON B.Name = T.TagName
        WHERE B.UserId = UAS.UserId
        AND B.Class = 1
        AND B.TagBased = TRUE
        AND HIP.PostTypeId = 1
        AND HIP.Tags IS NOT NULL
        AND LENGTH(HIP.Tags) > 2
        AND EXISTS (
            SELECT 1 FROM UNNEST(string_to_array(SUBSTRING(HIP.Tags, 2, LENGTH(HIP.Tags)-2), '><')) AS post_tag
            WHERE post_tag = T.TagName
        )
    ) AS HasRelatedGoldTagBadgeForPost,
    COALESCE(SUBSTRING(HIP.Title, 1, 60), 'No Title Available (' || HIP.PostTypeId || ')') AS ShortenedPostTitle,
    (HIP.ClosedDateSentinel <> TIMESTAMP '9999-12-31 00:00:00') AS IsPostClosed,
    (
        SELECT ROUND(AVG(EXTRACT(EPOCH FROM (ETA.EditDate - ETA.PreviousEditDate))) / 3600, 2)
        FROM PostEditTimeline ETA
        WHERE ETA.PostId = HIP.PostId
        AND ETA.EditorUserId = UAS.UserId
        AND ETA.EditDate <> ETA.PreviousEditDate
        AND ETA.TextLengthChange > 50
    ) AS AvgSignificantEditIntervalHours,
    NTILE(5) OVER (ORDER BY UAS.TotalUpVotes DESC) AS UpVoteDecile,
    LE.EditedTextContent AS LatestMajorEditTextSnippet,
    LE.EditDate AS LatestMajorEditDate,
    LE.TextLengthChange AS LatestEditLengthChange,
    (UAS.TotalDownVotes > (SELECT AVG(U2.DownVotes) * 2 FROM Users U2 WHERE U2.Reputation > 1000)) AS IsHighDownvoteUser
FROM UserActivitySummary UAS
INNER JOIN HighImpactPosts HIP ON UAS.UserId = HIP.OwnerUserId
LEFT JOIN (SELECT * FROM PostEditTimeline WHERE rn_latest_edit_per_post = 1 AND TextLengthChange > 100) LE ON HIP.PostId = LE.PostId AND UAS.UserId = LE.EditorUserId
WHERE
    UAS.Reputation > 7500
    AND UAS.TotalPosts >= 15
    AND COALESCE(HIP.PostScore, 0) > 8
    AND HIP.ViewCount > 5000
    AND UAS.LastKnownActivity >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year 6 months'
    AND HIP.ImpactCategory IN ('HighTrafficQuestion', 'HighScoreRecentAnswer', 'AcceptedFavoriteQuestion')
    AND NOT (HIP.PostTypeId = 1 AND (HIP.ClosedDateSentinel <> TIMESTAMP '9999-12-31 00:00:00') AND HIP.ImpactCategory = 'OtherImpact')
    AND HIP.DuplicateLinkedPostCount = 0
    AND HIP.Tags IS NOT NULL
    AND LENGTH(HIP.Tags) > 2
    AND (
        (UAS.SelfAcceptedAnswers > 0 AND UAS.QuestionsWithAcceptedAnswer > 0 AND UAS.DistinctBadgesCount > 7 AND UAS.TotalUpVotes > 1000)
        OR
        (UAS.QuestionsPosted > 8 AND UAS.AnswersPosted > 8 AND COALESCE(HIP.PostScore, 0) >= 20 AND HIP.AverageCommentScore IS NOT NULL AND HIP.AverageCommentScore > 2.5)
    )

UNION ALL

SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.QuestionsPosted,
    UAS.AnswersPosted,
    UAS.TotalPostScore,
    UAS.LastKnownActivity,
    UAS.DistinctBadgesCount,
    UAS.QuestionsWithAcceptedAnswer,
    UAS.SelfAcceptedAnswers,
    FRP.PostId,
    FRP.Title AS PostTitle,
    FRP.Score AS PostScore,
    FRP.ViewCount,
    'FoundationalReferencedContent' AS ImpactCategory,
    NULL AS AverageCommentScore,
    ROUND(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - UAS.UserCreationDate)) / 86400, 2) AS UserAgeInDays,
    ROUND(EXTRACT(EPOCH FROM (FRP.CreationDate - UAS.UserCreationDate)) / 3600, 2) AS PostAgeRelativeToUserCreationHours,
    NTILE(4) OVER (ORDER BY UAS.Reputation * FRP.IncomingLinkCount DESC) AS HistoricalInfluenceDecile,
    (
        SELECT CASE WHEN COUNT(C.Id) > 0 THEN TRUE ELSE FALSE END
        FROM Comments C
        WHERE C.UserId = UAS.UserId
        AND C.PostId = FRP.PostId
        AND C.UserId != (SELECT P_inner.OwnerUserId FROM Posts P_inner WHERE P_inner.Id = FRP.PostId)
    ) AS HasCrossCommentedOnPost,
    COALESCE(SUBSTRING(FRP.Title, 1, 60), 'No Title Found (Foundational)') AS ShortenedPostTitle,
    FALSE AS IsPostClosed,
    NULL AS AvgSignificantEditIntervalHours,
    NTILE(5) OVER (ORDER BY UAS.TotalUpVotes DESC) AS UpVoteDecile,
    NULL AS LatestMajorEditTextSnippet,
    NULL AS LatestMajorEditDate,
    NULL AS LatestEditLengthChange,
    (UAS.TotalDownVotes > (SELECT AVG(U2.DownVotes) FROM Users U2 WHERE U2.Reputation > 5000) * 1.5) AS IsHighDownvoteUser
FROM UserActivitySummary UAS
INNER JOIN FoundationalReferencedPosts FRP ON UAS.UserId = FRP.OwnerUserId
INNER JOIN UsersWithHighEngagementAndLowDownvotes UHELD ON UAS.UserId = UHELD.UserId

EXCEPT

SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.QuestionsPosted,
    UAS.AnswersPosted,
    UAS.TotalPostScore,
    UAS.LastKnownActivity,
    UAS.DistinctBadgesCount,
    UAS.QuestionsWithAcceptedAnswer,
    UAS.SelfAcceptedAnswers,
    FRP.PostId,
    FRP.Title AS PostTitle,
    FRP.Score AS PostScore,
    FRP.ViewCount,
    'FoundationalReferencedContent' AS ImpactCategory,
    NULL AS AverageCommentScore,
    ROUND(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - UAS.UserCreationDate)) / 86400, 2) AS UserAgeInDays,
    ROUND(EXTRACT(EPOCH FROM (FRP.CreationDate - UAS.UserCreationDate)) / 3600, 2) AS PostAgeRelativeToUserCreationHours,
    NTILE(4) OVER (ORDER BY UAS.Reputation * FRP.IncomingLinkCount DESC) AS HistoricalInfluenceDecile,
    (
        SELECT CASE WHEN COUNT(C.Id) > 0 THEN TRUE ELSE FALSE END
        FROM Comments C
        WHERE C.UserId = UAS.UserId
        AND C.PostId = FRP.PostId
        AND C.UserId != (SELECT P_inner.OwnerUserId FROM Posts P_inner WHERE P_inner.Id = FRP.PostId)
    ) AS HasCrossCommentedOnPost,
    COALESCE(SUBSTRING(FRP.Title, 1, 60), 'No Title Found (Foundational)') AS ShortenedPostTitle,
    FALSE AS IsPostClosed,
    NULL AS AvgSignificantEditIntervalHours,
    NTILE(5) OVER (ORDER BY UAS.TotalUpVotes DESC) AS UpVoteDecile,
    NULL AS LatestMajorEditTextSnippet,
    NULL AS LatestMajorEditDate,
    NULL AS LatestEditLengthChange,
    (UAS.TotalDownVotes > (SELECT AVG(U2.DownVotes) FROM Users U2 WHERE U2.Reputation > 5000) * 1.5) AS IsHighDownvoteUser
FROM UserActivitySummary UAS
INNER JOIN FoundationalReferencedPosts FRP ON UAS.UserId = FRP.OwnerUserId
INNER JOIN UsersWithHighEngagementAndLowDownvotes UHELD ON UAS.UserId = UHELD.UserId
WHERE EXISTS (
    SELECT 1 FROM PostHistory PH_EXCEPT
    WHERE PH_EXCEPT.UserId = UAS.UserId
    AND PH_EXCEPT.PostHistoryTypeId = 12
    AND PH_EXCEPT.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 years'
)
ORDER BY Reputation DESC, PostScore DESC, UserAgeInDays DESC;