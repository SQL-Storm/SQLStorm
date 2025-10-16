-- {"query": "19041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 869} 

WITH UserActivityMetrics AS (
    -- Aggregates user's post creation, answer counts, total scores across their posts,
    -- average score per post type, total comments, and last activity.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        MAX(U.LastAccessDate) AS UserLastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCount,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCount,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 1) AS AvgQuestionScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT V.PostId) AS PostsVotedOnCount,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) AS TotalUpVotesGiven,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) AS TotalDownVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN COALESCE(V.BountyAmount, 0) ELSE 0 END) AS TotalBountyGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostEngagementDetails AS (
    -- Extracts tags, calculates comment count and average comment score per post,
    -- and checks if a post has an accepted answer.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        COALESCE(P.Title, 'No Title Provided') AS PostTitle,
        -- Safely extract tags as an array; handle empty or malformed tag strings
        CASE WHEN P.Tags IS NOT NULL AND LENGTH(TRIM(P.P.Tags)) > 2
             THEN string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')
             ELSE NULL END AS TagsArray,
        -- Correlated subquery for average comment score
        (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS AvgCommentScore,
        -- Correlated subquery for count of distinct users who commented
        (SELECT COUNT(DISTINCT C_sub.UserId) FROM Comments C_sub WHERE C_sub.PostId = P.Id AND C_sub.UserId IS NOT NULL) AS DistinctCommentersCount,
        -- Correlated subquery for total post links (linked to or duplicating this post)
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id OR PL.RelatedPostId = P.Id) AS TotalLinksCount,
        P.ClosedDate,
        CASE WHEN P.ClosedDate IS NOT NULL THEN
            (SELECT CR.Name FROM CloseReasonTypes CR
             JOIN PostHistory PH_close ON CR.Id =