-- {"query": "1486.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3154} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 AND V.PostId IS NOT NULL THEN 1 ELSE 0 END) AS TotalUpVotesCastByOwner,
        SUM(CASE WHEN V.VoteTypeId = 3 AND V.PostId IS NOT NULL THEN 1 ELSE 0 END) AS TotalDownVotesCastByOwner,
        SUM(P.Score) AS TotalScoreOnOwnedPosts,
        MAX(U.LastAccessDate) AS LastSeenDate,
        COUNT(DISTINCT B.Name) AS DistinctBadgesCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    WHERE U.CreationDate >= '2010-01-01' AND U.Reputation > 1000
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 5 AND SUM(COALESCE(P.Score, 0)) > 100
),
PostHistoricalMilestones AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS InitialScore,
        P.ViewCount AS InitialViewCount,
        P.CommentCount AS InitialCommentCount,
        P.AnswerCount AS InitialAnswerCount,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS LastEditDate,
        MIN(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS FirstCloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenDate,
        (
            SELECT MIN(C.CreationDate)
            FROM Comments AS C
            WHERE C.PostId = P.Id
            AND C.UserId IS DISTINCT FROM P.OwnerUserId -- First comment by someone other than the owner or anonymous
        ) AS FirstNonOwnerCommentDate,
        (
            SELECT MIN(A.CreationDate)
            FROM Posts AS A
            WHERE A.ParentId = P.Id AND A.PostTypeId = 2
        ) AS FirstAnswerDate,
        P.AcceptedAnswerId,
        (
            SELECT A_Accepted.CreationDate
            FROM Posts AS A_Accepted
            WHERE A_Accepted.Id = P.AcceptedAnswerId
        ) AS AcceptedAnswerCreationDate,
        (
            SELECT COALESCE(CR.Name, 'Unknown')
            FROM PostHistory PH_CR
            LEFT JOIN CloseReasonTypes CR ON
                CASE
                    WHEN PH_CR.Comment LIKE '%^([0-9]+)$%' THEN TRY_CAST(PH_CR.Comment AS SMALLINT) -- For new int-based close reasons
                    ELSE NULL -- Handle old string-based close reasons or other comments
                END = CR.Id
            WHERE PH_CR.PostId = P.Id AND PH_CR.PostHistoryTypeId = 10
            ORDER BY PH_CR.CreationDate
            LIMIT 1
        ) AS FirstCloseReason
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.PostTypeId = 1 AND P.CreationDate >= '2010-01-01'
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.CommentCount, P.AnswerCount, P.AcceptedAnswerId
    HAVING COALESCE(P.ViewCount, 0) > 500 AND COALESCE(P.AnswerCount, 0) > 0
),
PostTagAnalysis AS (
    SELECT
        P.Id AS PostId,
        STRING_AGG(T.TagName, ', ') AS AllTags,
        COUNT(DISTINCT T.Id) AS NumberOfTags,
        AVG(T.Count) AS AvgTagUsageCount,
        SUM(CASE WHEN T.IsModeratorOnly = true THEN 1 ELSE 0 END) AS ModeratorOnlyTagCount,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS UserPostRankByScoreViews,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId, DATE_TRUNC('month', P.CreationDate) ORDER BY P.CreationDate) AS PostSequenceInMonth
    FROM Posts AS P
    JOIN LATERAL UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName_Unnested ON TRUE
    JOIN Tags AS T ON TagName_Unnested = T.TagName
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY P.Id, P.OwnerUserId, P.Score, P.ViewCount, P.CreationDate
),
PostLinkAndVoteStats AS (
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT V.Id) AS TotalVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavorites,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateLinksCount,
        (
            SELECT SUM(V_Bounty.BountyAmount)
            FROM Votes V_Bounty
            WHERE V_Bounty.PostId = P.Id AND V_Bounty.VoteTypeId IN (8, 9)
        ) AS TotalBountyAmount
    FROM Posts AS P
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    WHERE P.PostTypeId = 1
    GROUP BY P.Id
)
SELECT
    -- User Information
    UAS.UserId,
    UAS.DisplayName AS OwnerDisplayName,
    UAS.Reputation AS OwnerReputation,
    UAS.TotalPostsCreated,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    NULLIF(UAS.TotalUpVotesCastByOwner, 0) / NULLIF(UAS.TotalDownVotesCastByOwner, 0)::NUMERIC AS OwnerVoteRatio,

    -- Post Core Metrics
    P.Id AS QuestionId,
    P.Title AS QuestionTitle,
    P.Score AS CurrentScore,
    P.ViewCount AS CurrentViewCount,
    P.AnswerCount AS CurrentAnswerCount,
    P.CommentCount AS CurrentCommentCount,
    LENGTH(P.Body) AS BodyLength,
    LENGTH(P.Title) AS TitleLength,
    SUBSTRING(P.Body, 1, 100) AS BodyExcerpt, -- First 100 chars of body

    -- Post Lifecycle and History
    PHM.PostCreationDate,
    PHM.FirstEditDate,
    PHM.LastEditDate,
    PHM.FirstCloseDate,
    PHM.LastReopenDate,
    PHM.FirstNonOwnerCommentDate,
    PHM.FirstAnswerDate,
    PHM.AcceptedAnswerCreationDate,
    PHM.FirstCloseReason,
    EXTRACT(EPOCH FROM (PHM.FirstAnswerDate - PHM.PostCreationDate)) / 3600 AS TimeToFirstAnswerHours, -- Time to first answer in hours
    EXTRACT(EPOCH FROM (PHM.AcceptedAnswerCreationDate - PHM.PostCreationDate)) / 86400 AS TimeToAcceptedAnswerDays, -- Time to accepted answer in days
    EXTRACT(EPOCH FROM (COALESCE(PHM.LastReopenDate, P.ClosedDate) - PHM.FirstCloseDate)) / 86400 AS CloseToReopenDays, -- Duration it was closed in days
    COALESCE(P.ClosedDate, P.LastActivityDate) AS EffectiveLastActivityDate, -- Use ClosedDate if present, else LastActivityDate
    
    -- Tag Information
    PTA.AllTags,
    PTA.NumberOfTags,
    PTA.AvgTagUsageCount,
    PTA.ModeratorOnlyTagCount,

    -- Engagement Metrics
    PLVS.TotalVotesReceived,
    PLVS.TotalUpvotesReceived,
    PLVS.TotalDownvotesReceived,
    PLVS.TotalFavorites,
    PLVS.LinkedPostsCount,
    PLVS.DuplicateLinksCount,
    COALESCE(PLVS.TotalBountyAmount, 0) AS TotalBountyAmount,
    NULLIF(PLVS.TotalUpvotesReceived, 0) / NULLIF(PLVS.TotalDownvotesReceived, 0)::NUMERIC AS UpvoteToDownvoteRatio,
    
    -- Window Functions
    RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserMostRecentPostRank,
    NTILE(5) OVER (ORDER BY P.Score DESC, P.ViewCount DESC, P.AnswerCount DESC) AS EngagementQuintile,
    LAG(P.CreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostCreationDate,
    LEAD(P.CreationDate, 1, '9999-12-31'::timestamp) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostCreationDate,
    AVG(P.Score) OVER (PARTITION BY DATE_TRUNC('month', P.CreationDate)) AS AvgMonthlyQuestionScore,
    AVG(P.ViewCount) OVER (PARTITION BY PTA.NumberOfTags) AS AvgViewCountForTagComplexity,

    -- Complex expressions and NULL logic
    CASE
        WHEN P.AcceptedAnswerId IS NOT NULL AND PHM.FirstCloseDate IS NULL THEN 'Resolved & Open'
        WHEN P.AcceptedAnswerId IS NOT NULL AND PHM.FirstCloseDate IS NOT NULL THEN 'Resolved & Closed'
        WHEN P.AcceptedAnswerId IS NULL AND PHM.FirstCloseDate IS NULL AND P.AnswerCount > 0 THEN 'Unresolved with Answers'
        WHEN P.AcceptedAnswerId IS NULL AND PHM.FirstCloseDate IS NOT NULL THEN 'Unresolved & Closed'
        ELSE 'No Answers Yet'
    END AS QuestionStatus,
    COALESCE(P.CommunityOwnedDate, P.LastEditDate, P.CreationDate) AS PostEffectiveDate, -- Example of COALESCE for date priority
    P.ContentLicense,
    (COALESCE(P.Score, 0) * COALESCE(P.ViewCount, 0)) / NULLIF(COALESCE(P.AnswerCount, 0) + COALESCE(P.CommentCount, 0) + 1, 0) AS EngagementIndex -- A made-up index for complexity

FROM Posts AS P
INNER JOIN UserActivitySummary AS UAS ON P.OwnerUserId = UAS.UserId
INNER JOIN PostHistoricalMilestones AS PHM ON P.Id = PHM.PostId
INNER JOIN PostTagAnalysis AS PTA ON P.Id = PTA.PostId
INNER JOIN PostLinkAndVoteStats AS PLVS ON P.Id = PLVS.PostId
WHERE P.PostTypeId = 1 -- Only questions
  AND P.Score > 50
  AND P.ViewCount > 1000
  AND P.AnswerCount >= 1
  AND P.LastActivityDate IS NOT NULL
  AND P.CreationDate >= '2015-01-01' -- Focus on more recent, active questions
  AND (LOWER(P.Body) LIKE '%code%' OR LOWER(P.Body) LIKE '%error%' OR LOWER(P.Body) LIKE '%problem%') -- Text search in body
  AND NOT (PHM.FirstCloseReason = 'Duplicate' AND PLVS.DuplicateLinksCount > 0) -- Filter out questions primarily closed as duplicates that also have duplicate links
  AND P.Title IS NOT NULL AND LENGTH(TRIM(P.Title)) > 10
ORDER BY P.LastActivityDate DESC, EngagementIndex DESC
LIMIT 500;
