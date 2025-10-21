-- {"query": "50094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1143} 

WITH TopTags AS (
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 5
),
TaggedQuestions AS (
    SELECT Q.Id
    FROM Posts AS Q
    JOIN TopTags ON Q.Tags LIKE '%<' || TopTags.TagName || '>%'
    WHERE Q.PostTypeId = 1
),
UserAnswerStats AS (
    SELECT
        A.OwnerUserId,
        EXTRACT(YEAR FROM A.CreationDate) AS ActivityYear,
        COUNT(A.Id) AS NumAnswers,
        SUM(A.Score) AS TotalAnswerScore,
        (array_agg(A.Id ORDER BY A.Score DESC, A.CreationDate DESC))[1] AS TopAnswerId
    FROM Posts AS A
    WHERE A.ParentId IN (SELECT Id FROM TaggedQuestions)
      AND A.PostTypeId = 2
      AND A.OwnerUserId IS NOT NULL
    GROUP BY A.OwnerUserId, EXTRACT(YEAR FROM A.CreationDate)
),
UserBadgeStats AS (
    SELECT
        UserId,
        EXTRACT(YEAR FROM Date) AS BadgeYear,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges
    FROM Badges
    GROUP BY UserId, EXTRACT(YEAR FROM Date)
),
UserVoteStats AS (
    SELECT
        UserId,
        EXTRACT(YEAR FROM CreationDate) AS VoteYear,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpvotesCast,
        COUNT(CASE WHEN VoteTypeId = 5 THEN 1 END) AS FavoritesGiven
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId, EXTRACT(YEAR FROM CreationDate)
),
CombinedAnnualStats AS (
    SELECT UserId, ActivityYear AS Year FROM UserAnswerStats
    UNION
    SELECT UserId, BadgeYear FROM UserBadgeStats
    UNION
    SELECT UserId, VoteYear FROM UserVoteStats
),
RankedUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        T.Year AS EngagementYear,
        (
            COALESCE(ANS.NumAnswers, 0) * 5 +
            COALESCE(ANS.TotalAnswerScore, 0) +
            COALESCE(BAD.GoldBadges, 0) * 25 +
            COALESCE(BAD.SilverBadges, 0) * 10 +
            COALESCE(VOT.UpvotesCast, 0) * 0.5 +
            COALESCE(VOT.FavoritesGiven, 0) * 2
        ) AS EngagementScore,
        COALESCE(ANS.NumAnswers, 0) AS NumAnswers,
        COALESCE(ANS.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(BAD.GoldBadges, 0) AS GoldBadges,
        ANS.TopAnswerId,
        ROW_NUMBER() OVER(PARTITION BY T.Year ORDER BY
            (
                COALESCE(ANS.NumAnswers, 0) * 5 +
                COALESCE(ANS.TotalAnswerScore, 0) +
                COALESCE(BAD.GoldBadges, 0) * 25 +
                COALESCE(BAD.SilverBadges, 0) * 10 +
                COALESCE(VOT.UpvotesCast, 0) * 0.5 +
                COALESCE(VOT.FavoritesGiven, 0) * 2
            ) DESC, U.Reputation DESC
        ) as Rank
    FROM CombinedAnnualStats T
    JOIN Users U ON T.UserId = U.Id
    LEFT JOIN UserAnswerStats ANS ON T.UserId = ANS.OwnerUserId AND T.Year = ANS.ActivityYear
    LEFT JOIN UserBadgeStats BAD ON T.UserId = BAD.UserId AND T.Year = BAD.BadgeYear
    LEFT JOIN UserVoteStats VOT ON T.UserId = VOT.UserId AND T.Year = VOT.VoteYear
    WHERE
        U.Reputation > 1500 AND U.CreationDate < (CURRENT_DATE - INTERVAL '3 year')
),
Finalists AS (
    SELECT * FROM RankedUsers WHERE Rank <= 5
)
SELECT
    F.EngagementYear,
    F.Rank,
    F.UserId,
    F.DisplayName,
    F.Reputation,
    CAST(F.EngagementScore AS DECIMAL(10, 2)) AS EngagementScore,
    F.NumAnswers,
    F.TotalAnswerScore,
    F.GoldBadges,
    LastComment.Text AS LastCommentOnTopAnswer
FROM Finalists F
LEFT JOIN LATERAL (
    SELECT C.Text
    FROM Comments C
    WHERE C.PostId = F.TopAnswerId
    ORDER BY C.CreationDate DESC
    LIMIT 1
) AS LastComment ON TRUE
ORDER BY F.EngagementYear DESC, F.Rank ASC;
