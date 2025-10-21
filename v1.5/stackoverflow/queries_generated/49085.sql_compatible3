WITH UserPostEngagement AS (
    SELECT
        P.OwnerUserId AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        SUM(P.Score) AS TotalPostScore,
        SUM(P.ViewCount) AS TotalPostViews,
        SUM(P.CommentCount) AS TotalPostCommentsReceived,
        SUM(P.FavoriteCount) AS TotalPostFavoritesReceived,
        COUNT(DISTINCT P.Id) AS TotalPostsPublished,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPublished,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPublished,
        MAX(P.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT CASE WHEN P_Parent.AcceptedAnswerId = P.Id THEN P.Id END) AS AcceptedAnswersGiven,
        SUM(CASE WHEN P_Parent.AcceptedAnswerId = P.Id THEN P.Score ELSE 0 END) AS ScoreFromAcceptedAnswers,
        SUM(CASE WHEN P.PostTypeId = 1 AND (LOWER(P.Tags) LIKE '%' || LOWER('<sql>') || '%' OR LOWER(P.Tags) LIKE '%' || LOWER('<database>') || '%') THEN 1 ELSE 0 END) AS SqlDatabaseQuestions,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL AND (P.ClosedDate - P.CreationDate) < INTERVAL '24 hour' THEN 1 ELSE 0 END) AS QuicklyClosedQuestions,
        ARRAY_AGG(DISTINCT T.tag) FILTER (WHERE P.PostTypeId = 1 AND T.tag IS NOT NULL) AS QuestionTagsArray
    FROM Posts P
    INNER JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN Posts P_Parent ON P.PostTypeId = 2 AND P.ParentId = P_Parent.Id
    LEFT JOIN LATERAL (
        SELECT T.tag
        FROM UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><')) AS T(tag)
    ) AS T ON P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
      AND P.Score >= 0
    GROUP BY P.OwnerUserId, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) >= 20
),
UserEngagementActivity AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT C.Id) AS CommentsMade,
        SUM(CASE WHEN C.Score > 0 THEN C.Score ELSE 0 END) AS TotalCommentScore,
        COUNT(DISTINCT V.PostId) AS UniquePostsVotedOn,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN V.Id END) AS UpvotesGiven,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN V.Id END) AS DownvotesGiven
    FROM Users U
    LEFT JOIN Comments C ON U.Id = C.UserId AND C.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
    LEFT JOIN Votes V ON U.Id = V.UserId AND V.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
    WHERE U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
    GROUP BY U.Id
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges B
    WHERE B.Date >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
    GROUP BY B.UserId
)
SELECT
    UPE.UserId,
    UPE.DisplayName,
    UPE.Reputation,
    UPE.TotalPostsPublished,
    UPE.TotalPostScore,
    UPE.AcceptedAnswersGiven,
    UPE.ScoreFromAcceptedAnswers,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UEA.CommentsMade, 0) AS CommentsMade,
    COALESCE(UEA.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(array_length(UPE.QuestionTagsArray, 1), 0) AS DistinctQuestionTags,
    (
        UPE.TotalPostScore * 0.5 +
        COALESCE(UPE.ScoreFromAcceptedAnswers, 0) * 1.5 +
        (CASE WHEN UPE.QuestionsPublished > 0 THEN UPE.TotalPostViews / UPE.QuestionsPublished ELSE 0 END) * 0.01 +
        COALESCE(UBS.GoldBadges, 0) * 100 +
        COALESCE(UBS.SilverBadges, 0) * 20 +
        COALESCE(UBS.BronzeBadges, 0) * 5 +
        COALESCE(UEA.CommentsMade, 0) * 0.1 +
        COALESCE(UEA.UpvotesGiven, 0) * 0.05 +
        UPE.SqlDatabaseQuestions * 50 +
        (COALESCE(array_length(UPE.QuestionTagsArray, 1), 0)) * 2 +
        (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - UPE.LastPostActivity)) / 3600 / 24) * -0.01 -
        (UPE.QuicklyClosedQuestions * 20)
    ) AS CompositeInfluenceScore,
    RANK() OVER (ORDER BY (
        UPE.TotalPostScore * 0.5 +
        COALESCE(UPE.ScoreFromAcceptedAnswers, 0) * 1.5 +
        (CASE WHEN UPE.QuestionsPublished > 0 THEN UPE.TotalPostViews / UPE.QuestionsPublished ELSE 0 END) * 0.01 +
        COALESCE(UBS.GoldBadges, 0) * 100 +
        COALESCE(UBS.SilverBadges, 0) * 20 +
        COALESCE(UBS.BronzeBadges, 0) * 5 +
        COALESCE(UEA.CommentsMade, 0) * 0.1 +
        COALESCE(UEA.UpvotesGiven, 0) * 0.05 +
        UPE.SqlDatabaseQuestions * 50 +
        (COALESCE(array_length(UPE.QuestionTagsArray, 1), 0)) * 2 +
        (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - UPE.LastPostActivity)) / 3600 / 24) * -0.01 -
        (UPE.QuicklyClosedQuestions * 20)
    ) DESC) AS InfluenceRank
FROM UserPostEngagement UPE
LEFT JOIN UserEngagementActivity UEA ON UPE.UserId = UEA.UserId
LEFT JOIN UserBadgeSummary UBS ON UPE.UserId = UBS.UserId
WHERE UPE.TotalPostsPublished >= 20
  AND UPE.Reputation >= 1000
  AND UPE.LastPostActivity >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 year')
ORDER BY InfluenceRank ASC, UPE.UserId ASC
FETCH FIRST 100 ROWS ONLY;