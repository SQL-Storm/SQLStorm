-- {"query": "1787.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1972} 

WITH UserEngagementSummary AS (
    -- CTE 1: Summarize core user engagement metrics, filtering for active and moderately reputable users.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        U.Views AS ProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        SUM(P.Score) AS SumPostScoreByOwner,
        AVG(P.Score) AS AvgPostScoreByOwner,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(P.LastActivityDate) AS LastPostActivity,
        (U.UpVotes + U.DownVotes) AS TotalVotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation >= 500 AND U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '2 year'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
PostDetailAggregates AS (
    -- CTE 2: Aggregate detailed post metrics, including parsing tags and calculating body length.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        LENGTH(P.Body) AS BodyLength,
        COALESCE(P.Title, 'No Title') AS PostTitle, -- NULL logic
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'))) AS TagName -- String expression + unnest
    FROM Posts P
    WHERE P.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
    AND P.OwnerUserId IS NOT NULL
    AND P.Body IS NOT NULL
),
RecentCommentActivity AS (
    -- CTE 3: Analyze recent comments made by users and on their posts.
    SELECT
        C.UserId,
        C.PostId,
        C.CreationDate AS CommentCreationDate,
        C.Score AS CommentScore,
        LENGTH(C.Text) AS CommentLength,
        ROW_NUMBER() OVER (PARTITION BY C.UserId, C.PostId ORDER BY C.CreationDate DESC) AS rn -- Window function
    FROM Comments C
    WHERE C.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
),
PostHistoryTimeline AS (
    -- CTE 4: Track post history events, especially edits and closures, and link to CloseReasonTypes.
    SELECT
        PH.PostId,
        PH.UserId AS EditorOrVoterUserId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        COALESCE(CRT.Name, 'N/A') AS CloseReason, -- NULL logic
        PH.Comment IS NOT NULL AS HasComment
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment::smallint = CRT.Id -- Complex predicate/join condition
    WHERE PH.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
)
-- Main Query: Combine information to identify influential content creators and their contributions.
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.GoldBadges,
    UES.TotalPostsByOwner,
    UES.SumPostScoreByOwner,
    UES.AvgPostScoreByOwner,
    UES.LastAccessDate,
    UES.ProfileViews,
    SUM(CASE WHEN PDA.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
    SUM(CASE WHEN PDA.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
    SUM(CASE WHEN PDA.PostTypeId = 1 AND PDA.ViewCount > 1000 THEN 1 ELSE 0 END) AS PopularQuestions,
    SUM(CASE WHEN PDA.PostTypeId = 2 AND PDA.PostScore >= 10 THEN 1 ELSE 0 END) AS HighScoringAnswers,
    COUNT(DISTINCT CASE WHEN PDA.AcceptedAnswerId IS NOT NULL AND PDA.PostTypeId = 1 THEN PDA.PostId END) AS QuestionsWithAcceptedAnswers,
    SUM(CASE WHEN PDA.TagName = 'sql' OR PDA.TagName = 'database' OR PDA.TagName = 'performance' THEN 1 ELSE 0 END) AS RelevantTagPosts,
    AVG(NULLIF(PDA.BodyLength, 0)) AS AvgBodyLengthOfPosts, -- Complicated calculation with NULLIF
    SUM(RCA.CommentScore) AS TotalRecentCommentScore,
    COUNT(DISTINCT PH.PostId) FILTER (WHERE PH.HistoryTypeName LIKE '%Edit%' AND PH.EditorOrVoterUserId = UES.UserId) AS RecentEditsByThisUser,
    COUNT(DISTINCT CASE WHEN PH.HistoryTypeName LIKE '%Closed%' AND PH.EditorOrVoterUserId IS NULL THEN PH.PostId END) AS CommunityClosedPosts, -- NULL logic, indicating community closure
    MAX(CASE WHEN PDA.PostTypeId = 1 AND PDA.TagName = 'postgresql' THEN PDA.PostScore ELSE 0 END) AS MaxPostgreSqlQuestionScore,
    -- Correlated subquery: Average score of answers to their own questions
    (
        SELECT AVG(AP.PostScore)
        FROM PostDetailAggregates AP
        WHERE AP.ParentId IN (SELECT Q.PostId FROM PostDetailAggregates Q WHERE Q.OwnerUserId = UES.UserId AND Q.PostTypeId = 1)
        AND AP.PostTypeId = 2
    ) AS AvgAnswerScoreToOwnQuestions,
    -- Window function: Rank users by their average post score within their reputation tier
    RANK() OVER (PARTITION BY FLOOR(UES.Reputation / 10000) ORDER BY UES.AvgPostScoreByOwner DESC, UES.GoldBadges DESC) AS RankInReputationTier
FROM UserEngagementSummary UES
LEFT JOIN PostDetailAggregates PDA ON UES.UserId = PDA.OwnerUserId
LEFT JOIN RecentCommentActivity RCA ON UES.UserId = RCA.UserId AND RCA.rn = 1 -- Get only the latest comment activity per post
LEFT JOIN PostHistoryTimeline PH ON UES.UserId = PH.EditorOrVoterUserId OR (UES.UserId = PDA.OwnerUserId AND PH.PostId = PDA.PostId)
WHERE UES.GoldBadges > 0
  AND UES.TotalPostsByOwner >= 10
  AND UES.AvgPostScoreByOwner > 2
  AND UES.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' -- Predicate for recency
GROUP BY
    UES.UserId, UES.DisplayName, UES.Reputation, UES.GoldBadges, UES.TotalPostsByOwner,
    UES.SumPostScoreByOwner, UES.AvgPostScoreByOwner, UES.LastAccessDate, UES.ProfileViews
HAVING
    SUM(CASE WHEN PDA.PostTypeId = 1 AND PDA.ViewCount > 500 THEN 1 ELSE 0 END) >= 3 -- At least 3 popular questions
    AND SUM(CASE WHEN PDA.PostTypeId = 2 AND PDA.PostScore >= 5 THEN 1 ELSE 0 END) >= 5 -- At least 5 high-scoring answers
    AND (SUM(CASE WHEN PDA.TagName = 'sql' THEN 1 ELSE 0 END) + SUM(CASE WHEN PDA.TagName = 'database' THEN 1 ELSE 0 END)) > 0 -- At least one post related to 'sql' or 'database'
ORDER BY
    UES.Reputation DESC,
    PopularQuestions DESC,
    HighScoringAnswers DESC,
    AvgBodyLengthOfPosts DESC
LIMIT 100;
