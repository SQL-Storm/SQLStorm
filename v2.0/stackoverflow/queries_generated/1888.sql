-- {"query": "1888.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2665} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        COUNT(DISTINCT C.Id) AS CommentsPosted,
        COUNT(DISTINCT PH.PostId) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS PostsEdited, -- Edits to Title, Body, Tags
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceivedOnPosts, -- UpMod for their posts
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceivedOnPosts, -- DownMod for their posts
        SUM(CASE WHEN UV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGivenByMe, -- UpMod given by user
        SUM(CASE WHEN UV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGivenByMe, -- DownMod given by user
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN PostHistory AS PH ON U.Id = PH.UserId
    LEFT JOIN Votes AS PV ON P.Id = PV.PostId AND PV.VoteTypeId IN (2, 3) -- Votes on posts owned by user
    LEFT JOIN Votes AS UV ON U.Id = UV.UserId AND UV.VoteTypeId IN (2, 3) -- Votes cast by user
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostQualityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.AcceptedAnswerId,
        P.ClosedDate,
        P.Body,
        -- Complicated Expression: Calculate age in hours since last edit, defaulting to post creation if no edit
        COALESCE((EXTRACT(EPOCH FROM (NOW() - P.LastEditDate)) / 3600), (EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / 3600))::numeric AS LastActivityAgeHours,
        COALESCE(P.ViewCount, 0) AS ViewCountNonNull,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCountNonNull,
        -- Correlated Subquery 1: Average score of child answers for questions
        CASE
            WHEN P.PostTypeId = 1 THEN (
                SELECT AVG(A.Score)
                FROM Posts AS A
                WHERE A.ParentId = P.Id
                  AND A.PostTypeId = 2
            )
            ELSE NULL
        END AS AvgChildAnswerScore,
        -- Correlated Subquery 2: Check if any linked post is highly scored
        EXISTS (
            SELECT 1
            FROM PostLinks AS PL
            JOIN Posts AS LinkedP ON PL.RelatedPostId = LinkedP.Id
            WHERE PL.PostId = P.Id
              AND PL.LinkTypeId = 1 -- Linked
              AND LinkedP.Score > 50
        ) AS HasHighScoreLinkedPost
    FROM Posts AS P
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        -- String Expression: Parse tags from the Tags string, handling potential empty string after trimming
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(TRIM(P.Tags)) > 2 -- Ensure tags string is not empty or just "<>"
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.QuestionsAsked,
    UES.AnswersGiven,
    UES.CommentsPosted,
    UES.PostsEdited,
    UES.GoldBadges,
    UES.SilverBadges,
    UES.BronzeBadges,
    PQM.PostId,
    PQM.Title,
    PQM.PostTypeId,
    PQM.PostCreationDate,
    PQM.Score AS PostScore,
    PQM.ViewCount,
    PQM.FavoriteCount,
    PQM.CommentCount,
    PQM.LastActivityDate,
    PQM.LastActivityAgeHours,
    PQM.AvgChildAnswerScore,
    PQM.HasHighScoreLinkedPost,
    TA.TagName,
    T.Count AS TagGlobalCount,
    CR.Name AS ActualCloseReasonName,
    COALESCE(CR.Name, 'No Close Reason Specified') AS CoalescedCloseReason, -- NULL Logic
    PL.RelatedPostId AS LinkedOrDuplicatePostId,
    LT.Name AS LinkTypeName,
    PHT.HistoryDate AS PostLatestEditHistoryDate,
    PHT.PostHistoryTypeId AS PostLatestEditHistoryType,
    -- Complicated Calculation / Expression: Weighted engagement score for a post
    (PQM.Score * 0.4 + PQM.CommentCount * 0.2 + COALESCE(PQM.AvgChildAnswerScore, 0) * 0.3 + PQM.FavoriteCount * 0.1)::DECIMAL(10,2) AS WeightedPostEngagementScore,
    -- Conditional Expression & NULL Logic: Categorize post status
    CASE
        WHEN PQM.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answered'
        WHEN PQM.ClosedDate IS NOT NULL THEN 'Closed Question'
        WHEN PQM.AnswerCount > 0 AND PQM.AcceptedAnswerId IS NULL THEN 'Unaccepted Answered'
        WHEN PQM.PostTypeId = 1 AND PQM.AnswerCount = 0 THEN 'No Answers Yet'
        ELSE 'Other Post Type'
    END AS PostStatusCategory,
    -- Window Function 1: Rank posts by score within each PostTypeId
    RANK() OVER (PARTITION BY PQM.PostTypeId ORDER BY PQM.Score DESC, PQM.ViewCount DESC, PQM.PostCreationDate DESC) AS RankOverallScorePerType,
    -- Window Function 2: Calculate average score of all posts by the same user
    AVG(PQM.Score) OVER (PARTITION BY UES.UserId) AS AvgUserPostScore,
    -- Window Function 3 & Complicated Calculation: Days since the user's previous post
    EXTRACT(EPOCH FROM (PQM.PostCreationDate - LAG(PQM.PostCreationDate, 1, UES.UserCreationDate) OVER (PARTITION BY UES.UserId ORDER BY PQM.PostCreationDate))) / (60*60*24) AS DaysSincePreviousPost,
    -- String Expression: Categorize body length
    CASE
        WHEN LENGTH(PQM.Body) IS NULL THEN 'No Body'
        WHEN LENGTH(PQM.Body) < 250 THEN 'Short Body'
        WHEN LENGTH(PQM.Body) BETWEEN 250 AND 1500 THEN 'Medium Body'
        ELSE 'Long Body'
    END AS BodyLengthCategory
FROM UserEngagementSummary AS UES
INNER JOIN PostQualityMetrics AS PQM ON UES.UserId = PQM.OwnerUserId
LEFT JOIN PostLinks AS PL ON PQM.PostId = PL.PostId
LEFT JOIN LinkTypes AS LT ON PL.LinkTypeId = LT.Id
LEFT JOIN TagAnalysis AS TA ON PQM.PostId = TA.PostId
LEFT JOIN Tags AS T ON TA.TagName = T.TagName
-- Subquery for latest close reason (PostHistoryTypeId = 10)
LEFT JOIN (
    SELECT
        PH_Close.PostId,
        MAX(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN PH_Close.Comment END) AS LastCloseReasonId_Raw
    FROM PostHistory AS PH_Close
    WHERE PH_Close.PostHistoryTypeId = 10 -- Only interested in close events
    GROUP BY PH_Close.PostId
) AS LastPostCloseHistory ON PQM.PostId = LastPostCloseHistory.PostId
LEFT JOIN CloseReasonTypes AS CR ON CAST(LastPostCloseHistory.LastCloseReasonId_Raw AS SMALLINT) = CR.Id
-- Subquery for the latest edit history event (PostHistoryTypeId IN (4, 5, 6))
LEFT JOIN (
    SELECT
        sub.PostId,
        sub.CreationDate AS HistoryDate,
        sub.PostHistoryTypeId
    FROM (
        SELECT
            PH_Edit.PostId,
            PH_Edit.CreationDate,
            PH_Edit.PostHistoryTypeId,
            ROW_NUMBER() OVER (PARTITION BY PH_Edit.PostId ORDER BY PH_Edit.CreationDate DESC, PH_Edit.Id DESC) as rn
        FROM PostHistory AS PH_Edit
        WHERE PH_Edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    ) AS sub
    WHERE sub.rn = 1
) AS PHT ON PQM.PostId = PHT.PostId
WHERE UES.Reputation >= 10000 -- High reputation users
    AND PQM.PostTypeId = 1 -- Only questions
    AND PQM.Score > 20
    AND PQM.ViewCount > 500
    AND PQM.FavoriteCount > 2
    AND (PQM.ClosedDate IS NULL OR CR.Name IS NULL) -- Only open questions or questions with no explicit close reason
    AND PQM.LastActivityAgeHours > 24 * 90 -- Questions not active in the last 3 months
    AND PQM.HasHighScoreLinkedPost IS TRUE -- Has at least one highly scored linked post
    AND (TA.TagName LIKE '%sql%' OR TA.TagName LIKE '%database%' OR TA.TagName LIKE '%performance%') -- Specific tags
    AND NOT EXISTS ( -- Correlated Subquery: Exclude posts that were edited by the owner within 24 hours of creation
        SELECT 1
        FROM PostHistory AS PH_EarlyEdit
        WHERE PH_EarlyEdit.PostId = PQM.PostId
          AND PH_EarlyEdit.UserId = PQM.OwnerUserId
          AND PH_EarlyEdit.PostHistoryTypeId IN (4, 5, 6)
          AND PH_EarlyEdit.CreationDate < PQM.PostCreationDate + INTERVAL '24 hours'
    )
    AND PQM.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate > NOW() - INTERVAL '1 year') -- Correlated Subquery: ViewCount above average for recent questions
ORDER BY WeightedPostEngagementScore DESC, DaysSincePreviousPost DESC, UES.Reputation DESC
LIMIT 500;
