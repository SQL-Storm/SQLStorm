-- {"query": "1348.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 527} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - U.CreationDate)) / (60 * 60 * 24 * 365.25)) AS AccountAgeYears,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViewsReceived,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalPostFavoritesReceived,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges,
        MAX(P.CreationDate) AS LastPostCreationDate,
        MIN(P.CreationDate) AS FirstPostCreationDate,
        (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 5) AS TotalBookmarksMade,
        (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId IN (2)) AS TotalUpvotesMade,
        (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId IN (3)) AS TotalDownvotesMade,
        CASE WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 50 THEN TRUE ELSE FALSE END AS HasDetailedAboutMe
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.Owner