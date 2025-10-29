-- {"query": "1917.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3792} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.WebsiteUrl,
        U.Location,
        U.AboutMe,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(B.Date) AS LastBadgeAwardDate,
        (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(C.CreationDate) AS LatestCommentOnAnyPost
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.WebsiteUrl, U.Location, U.AboutMe
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.LastActivityDate,
        COALESCE(P.ClosedDate, (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10)) AS EffectiveClosedDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditRevisionCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosureEventDate,
        STRING_AGG(DISTINCT PH.Comment, ',') FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND PH.Comment ~ '^\d+$') AS CloseReasonIds, -- Aggregates actual CloseReasonId values
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate) AS RankByUserScoreAndViews
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.LastActivityDate, P.ClosedDate
),
TagAndLinkAnalysis AS (
    SELECT
        P.Id AS QuestionId,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        LOWER(P.Tags) LIKE '%<sql>%' OR LOWER(P.Tags) LIKE '%<database>%' OR LOWER(P.Tags) LIKE '%<postgresql>%' OR LOWER(P.Tags) LIKE '%<nosql>%' AS IsRelevantTechTag,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN LT.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount,
        MAX(CASE WHEN LT.Name = 'Duplicate' AND RPP.Score > 50 THEN RPP.Score ELSE 0 END) AS MaxScoreOfHighScoringDuplicate,
        STRING_AGG(DISTINCT CONCAT('ID:', RPP.Id, '|Score:', COALESCE(RPP.Score, 0)), ';') FILTER (WHERE LT.Name = 'Duplicate') AS DuplicatePostDetails,
        EXISTS (SELECT 1 FROM Posts A WHERE A.Id = P.AcceptedAnswerId AND A.Score > P.Score * 0.5) AS HasHighlyRatedAcceptedAnswer
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    LEFT JOIN Posts RPP ON PL.RelatedPostId = RPP.Id
    WHERE P.PostTypeId = 1 -- Only consider questions for this analysis
    GROUP BY P.Id, P.Title, P.Tags, P.AcceptedAnswerId
),
QualifiedUserPosts AS (
    SELECT
        PHM.PostId,
        PHM.PostTypeId,
        PHM.OwnerUserId,
        PHM.PostCreationDate,
        PHM.PostScore,
        PHM.ViewCount,
        PHM.AnswerCount,
        PHM.FavoriteCount,
        PHM.EffectiveClosedDate,
        PHM.TotalHistoryEntries,
        PHM.EditRevisionCount,
        PHM.CloseEventCount,
        PHM.LastClosureEventDate,
        PHM.CloseReasonIds,
        PHM.RankByUserScoreAndViews,
        TLA.Title,
        TLA.Tags,
        TLA.AcceptedAnswerId,
        TLA.IsRelevantTechTag,
        TLA.TotalLinkedPosts,
        TLA.DuplicateLinkCount,
        TLA.MaxScoreOfHighScoringDuplicate,
        TLA.DuplicatePostDetails,
        TLA.HasHighlyRatedAcceptedAnswer,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.TotalBadges,
        UAS.GoldBadges,
        UAS.UserCreationDate,
        UAS.UserLastAccessDate,
        UAS.WebsiteUrl,
        UAS.Location,
        UAS.AboutMe,
        UAS.TotalCommentsMade,
        UAS.LatestCommentOnAnyPost,
        -- Calculate relative score to user's average
        CAST(PHM.PostScore AS NUMERIC) / NULLIF((SELECT AVG(P_INNER.Score) FROM Posts P_INNER WHERE P_INNER.OwnerUserId = PHM.OwnerUserId AND P_INNER.PostTypeId = PHM.PostTypeId AND P_INNER.Score > 0), 0) AS RelativePostScoreToUserAvg,
        -- Correlated subquery for recent user comment
        (SELECT C.Text FROM Comments C WHERE C.UserId = PHM.OwnerUserId AND C.CreationDate > (CURRENT_DATE - INTERVAL '30 days') ORDER BY C.CreationDate DESC LIMIT 1) AS LatestUserCommentText,
        -- Another window function: Average score of posts by this user in the last year
        AVG(PHM.PostScore) OVER (PARTITION BY PHM.OwnerUserId ORDER BY PHM.PostCreationDate RANGE BETWEEN INTERVAL '1 year' PRECEDING AND CURRENT ROW) AS RollingAvgUserPostScoreLastYear,
        -- Check if user has specific badges related to 'Tags'
        EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UAS.UserId AND B.Name ILIKE ANY (ARRAY['%SQL%', '%Database%']) AND B.TagBased = TRUE) AS HasSpecificTagBadges
    FROM PostHistoricalMetrics PHM
    JOIN UserActivitySummary UAS ON PHM.OwnerUserId = UAS.UserId
    LEFT JOIN TagAndLinkAnalysis TLA ON PHM.PostId = TLA.QuestionId
    WHERE
        PHM.PostTypeId = 1 -- Focus on questions
        AND PHM.PostScore >= 10 -- Minimum score
        AND PHM.ViewCount >= 500 -- Minimum views
        AND PHM.EditRevisionCount >= 2 -- At least two edits
        AND PHM.AcceptedAnswerId IS NOT NULL -- Must have an accepted answer
        AND UAS.Reputation >= 1000 -- Influential users
        AND UAS.TotalBadges >= 5 -- Users with some badges
        AND TLA.IsRelevantTechTag -- Relevant tech tags
        AND (TLA.DuplicateLinkCount = 0 OR TLA.MaxScoreOfHighScoringDuplicate <= 100) -- Not a duplicate of a *very* high-scoring post
),
RankedQualifiedUserPosts AS (
    SELECT
        QUP.*,
        ROW_NUMBER() OVER (ORDER BY QUP.PostScore DESC, QUP.ViewCount DESC, QUP.EditRevisionCount DESC, QUP.Reputation DESC) AS GlobalPostRank,
        NTILE(10) OVER (ORDER BY QUP.PostScore DESC) AS PostScoreDecile,
        LAG(QUP.PostCreationDate, 1, QUP.UserCreationDate) OVER (PARTITION BY QUP.OwnerUserId ORDER BY QUP.PostCreationDate) AS PreviousPostCreationDate
    FROM QualifiedUserPosts QUP
),
FinalOutput AS (
    -- SELECT for Questions
    SELECT
        'Question' AS PostTypeCategory,
        RQUP.PostId,
        RQUP.Title,
        RQUP.Tags,
        RQUP.PostCreationDate,
        RQUP.PostScore,
        RQUP.ViewCount,
        RQUP.AnswerCount,
        RQUP.FavoriteCount,
        RQUP.EffectiveClosedDate,
        RQUP.EditRevisionCount,
        RQUP.CloseReasonIds,
        RQUP.DisplayName AS OwnerDisplayName,
        RQUP.Reputation AS OwnerReputation,
        RQUP.TotalBadges AS OwnerTotalBadges,
        RQUP.HasHighlyRatedAcceptedAnswer,
        RQUP.TotalLinkedPosts,
        RQUP.DuplicateLinkCount,
        RQUP.MaxScoreOfHighScoringDuplicate,
        RQUP.DuplicatePostDetails,
        RQUP.RelativePostScoreToUserAvg,
        RQUP.LatestUserCommentText,
        RQUP.RollingAvgUserPostScoreLastYear,
        RQUP.GlobalPostRank,
        RQUP.PostScoreDecile,
        AGE(RQUP.PostCreationDate, RQUP.PreviousPostCreationDate) AS TimeSincePreviousPost,
        CASE
            WHEN RQUP.EffectiveClosedDate IS NOT NULL AND RQUP.EffectiveClosedDate > RQUP.PostCreationDate THEN 'Closed'
            WHEN RQUP.AnswerCount = 0 THEN 'No Answers'
            WHEN RQUP.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
            ELSE 'Open'
        END AS PostStatusClassification,
        -- Complex String Expression
        UPPER(SUBSTRING(TRIM(COALESCE(RQUP.Location, 'Unknown Location')) || ' (' || COALESCE(RQUP.WebsiteUrl, 'No Website')) || ')', 1, 50)) AS OwnerLocationAndWebsiteInfo,
        RQUP.HasSpecificTagBadges,
        LENGTH(RQUP.AboutMe) AS OwnerAboutMeLength
    FROM RankedQualifiedUserPosts RQUP
    WHERE RQUP.RankByUserScoreAndViews <= 10 AND RQUP.GlobalPostRank <= 100 -- Top posts globally and per user
    AND RQUP.PostCreationDate BETWEEN (CURRENT_DATE - INTERVAL '5 years') AND CURRENT_DATE -- Filter recent activities
    AND NOT EXISTS (
        SELECT 1 FROM Comments C WHERE C.PostId = RQUP.PostId AND C.Text ILIKE '%spam%'
    )

    UNION ALL

    -- SELECT for highly-rated answers by the same set of qualified users, referencing their related questions
    SELECT
        'Answer' AS PostTypeCategory,
        P_ANS.Id AS PostId,
        P_QUES.Title AS Title, -- Title of the parent question
        P_QUES.Tags AS Tags,
        P_ANS.CreationDate AS PostCreationDate,
        P_ANS.Score AS PostScore,
        NULL::INT AS ViewCount, -- Answers don't have direct view counts
        NULL::INT AS AnswerCount,
        P_ANS.FavoriteCount,
        (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.PostId = P_ANS.Id AND PH.PostHistoryTypeId = 10) AS EffectiveClosedDate, -- Answers can be closed as well
        (SELECT COUNT(*) FROM PostHistory PH WHERE PH.PostId = P_ANS.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS EditRevisionCount,
        STRING_AGG(DISTINCT PH.Comment, ',') FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND PH.Comment ~ '^\d+$') AS CloseReasonIds,
        UAS.DisplayName AS OwnerDisplayName,
        UAS.Reputation AS OwnerReputation,
        UAS.TotalBadges AS OwnerTotalBadges,
        (P_QUES.AcceptedAnswerId = P_ANS.Id) AS HasHighlyRatedAcceptedAnswer, -- Is *this* answer the accepted one?
        NULL::BIGINT AS TotalLinkedPosts,
        NULL::BIGINT AS DuplicateLinkCount,
        NULL::INT AS MaxScoreOfHighScoringDuplicate,
        NULL::TEXT AS DuplicatePostDetails,
        CAST(P_ANS.Score AS NUMERIC) / NULLIF(AVG(P_INNER.Score) OVER (PARTITION BY P_INNER.OwnerUserId), 0) AS RelativePostScoreToUserAvg,
        (SELECT C.Text FROM Comments C WHERE C.UserId = UAS.UserId AND C.CreationDate > (CURRENT_DATE - INTERVAL '30 days') ORDER BY C.CreationDate DESC LIMIT 1) AS LatestUserCommentText,
        AVG(P_ANS.Score) OVER (PARTITION BY UAS.UserId ORDER BY P_ANS.CreationDate RANGE BETWEEN INTERVAL '1 year' PRECEDING AND CURRENT ROW) AS RollingAvgUserPostScoreLastYear,
        ROW_NUMBER() OVER (ORDER BY P_ANS.Score DESC, UAS.Reputation DESC, P_ANS.CreationDate DESC) AS GlobalPostRank,
        NTILE(10) OVER (ORDER BY P_ANS.Score DESC) AS PostScoreDecile,
        AGE(P_ANS.CreationDate, LAG(P_ANS.CreationDate, 1, UAS.UserCreationDate) OVER (PARTITION BY UAS.UserId ORDER BY P_ANS.CreationDate)) AS TimeSincePreviousPost,
        CASE
            WHEN P_QUES.AcceptedAnswerId = P_ANS.Id THEN 'Accepted Answer'
            WHEN P_ANS.Score >= 50 THEN 'High Scoring Answer'
            WHEN (SELECT COUNT(*) FROM Comments C WHERE C.PostId = P_ANS.Id) > 5 THEN 'Highly Commented'
            ELSE 'Other Answer'
        END AS PostStatusClassification,
        UPPER(SUBSTRING(TRIM(COALESCE(UAS.Location, 'Unknown Location')) || ' (' || COALESCE(UAS.WebsiteUrl, 'No Website')) || ')', 1, 50)) AS OwnerLocationAndWebsiteInfo,
        EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UAS.Id AND B.Name ILIKE ANY (ARRAY['%Answer%', '%Helpful%'])) AS HasSpecificTagBadges,
        LENGTH(UAS.AboutMe) AS OwnerAboutMeLength
    FROM Posts P_ANS
    JOIN Users UAS ON P_ANS.OwnerUserId = UAS.Id
    JOIN Posts P_QUES ON P_ANS.ParentId = P_QUES.Id AND P_QUES.PostTypeId = 1 -- Ensure parent is a question
    WHERE P_ANS.PostTypeId = 2 -- Only answers
      AND P_ANS.Score >= 20 -- High-scoring answers
      AND P_ANS.CreationDate BETWEEN (CURRENT_DATE - INTERVAL '5 years') AND CURRENT_DATE
      AND UAS.Reputation >= 500 -- Users with at least 500 reputation
      AND EXISTS (
            SELECT 1 FROM Badges B WHERE B.UserId = UAS.Id AND B.Class = 1 -- At least one gold badge
        )
)
SELECT * FROM FinalOutput
WHERE PostStatusClassification != 'No Answers' -- Further filter out less interesting categories
ORDER BY PostTypeCategory, GlobalPostRank, PostScore DESC
LIMIT 500;
