-- {"query": "1126.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1278} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates core user activity metrics, badge counts, and calculates a previous reputation for comparison.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(B.Id) AS TotalBadgesEarned,
        MAX(B.Date) AS LastBadgeDate,
        LAG(U.Reputation, 1, 0) OVER (ORDER BY U.Reputation DESC) AS PrevUserReputation, -- Window function: LAG
        (U.UpVotes - U.DownVotes) AS NetVotesGivenByOthers,
        U.Views AS ProfileViews
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes, U.Views
),
PostHistoryRaw AS (
    -- CTE 2: Extracts detailed post history events, including sequence numbering and potential next event types.
    -- Also attempts to derive the close reason name using a correlated subquery.
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryEventDate,
        PH.Comment AS HistoryComment,
        PH.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS EventSequenceNum, -- Window function: ROW_NUMBER
        LEAD(PH.PostHistoryTypeId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS NextHistoryEventType, -- Window function: LEAD
        CASE
            WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL THEN (
                SELECT CRT.Name FROM CloseReasonTypes CRT WHERE CRT.Id::varchar = PH.Comment -- Correlated subquery for close reason
            )
            ELSE NULL
        END AS CloseReasonName
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (2, 5, 10, 11) -- Initial Body, Edit Body, Post Closed, Post Reopened
),
PostBodyEvolution AS (
    -- CTE 3: Calculates initial and latest body lengths for posts, along with the last edit date.
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 2 THEN LENGTH(PH.Text) ELSE NULL END) AS InitialBodyLength,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN LENGTH(PH.Text) ELSE NULL END) AS LatestBodyEditLength,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 5) AS LastBodyEditDate -- Window function style aggregate with FILTER
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (2, 5) -- Initial Body, Edit Body
    GROUP BY PH.PostId
),
PostTagAnalysis AS (
    -- CTE 4: Parses post tags, counts unique tags, sums their popularity, and aggregates tag names.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        COUNT(DISTINCT tag_value) AS UniqueTagsOnPost,
        SUM(T.Count) AS TotalTagPopularityScore,
        STRING_AGG(T.TagName, ';') AS AllTagNames, -- String aggregation
        AVG(T.Count) FILTER (WHERE T.TagName IS NOT NULL) AS AvgTagPopularity -- Window function style aggregate with FILTER
    FROM Posts P
    LEFT JOIN LATERAL unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS tag_value ON P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- String functions and LATERAL UNNEST
    LEFT JOIN Tags T ON T.TagName = tag_value
    GROUP BY P.Id, P.OwnerUserId
),
PostStatusEvents AS (
    -- CTE 5: Uses a set operator (UNION ALL) to combine distinct closed and reopened post events.
    SELECT PostId, HistoryEventDate AS EventDate, 'Closed' AS EventType
    FROM PostHistoryRaw
    WHERE PostHistoryTypeId = 10
    UNION ALL
    SELECT PostId, HistoryEventDate AS EventDate, 'Reopened' AS EventType
    FROM PostHistoryRaw
    WHERE PostHistoryTypeId = 11
)
-- Main Query: Joins all CTEs and other tables, applies complex predicates, calculations, and window functions
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.TotalPostsOwned,
    UES.QuestionsAsked,
    UES.AnswersProvided,
    UES.TotalPostScoreOwned,
    UES.TotalCommentsMade,
    UES.TotalBadgesEarned,
    UES.LastBadgeDate,
    UES.PrevUserReputation,
    UES.NetVotesGivenByOthers,
    UES.ProfileViews,
    AVG(P.