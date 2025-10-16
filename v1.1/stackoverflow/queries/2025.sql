WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT V.Id) AS VoteCount
    FROM
        Users U
        LEFT JOIN Posts P ON U.Id = P.OwnerUserId
        LEFT JOIN Comments C ON U.Id = C.UserId
        LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName
),
HighlyActiveUsers AS (
    SELECT
        UserId,
        DisplayName,
        PostCount + CommentCount + VoteCount AS TotalActivity
    FROM
        UserActivity
    WHERE
        PostCount > 0 OR CommentCount > 0 OR VoteCount > 0
    ORDER BY TotalActivity DESC
    LIMIT 100
),
UserBadges AS (
    SELECT
        U.UserId,
        B.Class,
        COUNT(B.Id) AS BadgeCount
    FROM
        HighlyActiveUsers U
        INNER JOIN Badges B ON U.UserId = B.UserId
    GROUP BY
        U.UserId, B.Class
),
PostEngagement AS (
    SELECT
        Posts.Id AS PostId,
        SUM(CASE WHEN Votes.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS VoteEngagement,
        COALESCE(SUM(COALESCE(Posts.CommentCount,0)),0) AS CommentEngagement
    FROM
        Posts
        LEFT JOIN Votes ON Posts.Id = Votes.PostId
    GROUP BY
        Posts.Id
),
DetailedPosts AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        COALESCE(P.Score, 0) AS CurrentScore,
        COALESCE(PE.VoteEngagement, 0) AS VoteEngagement,
        COALESCE(PE.CommentEngagement, 0) AS CommentEngagement
    FROM
        Posts P
        LEFT JOIN PostEngagement PE ON P.Id = PE.PostId
    WHERE
        COALESCE(PE.VoteEngagement, 0) + COALESCE(PE.CommentEngagement, 0) > 0
),
RankedEngagement AS (
    SELECT
        DP.PostId,
        DP.Title,
        (DP.VoteEngagement + DP.CommentEngagement) AS TotalEngagement,
        ROW_NUMBER() OVER (ORDER BY (DP.VoteEngagement + DP.CommentEngagement) DESC) AS Rank
    FROM
        DetailedPosts DP
    WHERE
        DP.CurrentScore > 0
)
SELECT
    HU.UserId,
    HU.DisplayName,
    COALESCE(MAX(CASE WHEN UB.Class = 1 THEN UB.BadgeCount END), 0) AS GoldBadges,
    COALESCE(MAX(CASE WHEN UB.Class = 2 THEN UB.BadgeCount END), 0) AS SilverBadges,
    COALESCE(MAX(CASE WHEN UB.Class = 3 THEN UB.BadgeCount END), 0) AS BronzeBadges,
    RE.PostId,
    RE.Title,
    RE.TotalEngagement
FROM
    HighlyActiveUsers HU
    LEFT JOIN UserBadges UB ON HU.UserId = UB.UserId
    JOIN RankedEngagement RE ON HU.UserId = (
        SELECT P2.OwnerUserId
        FROM Posts P2
        WHERE P2.Id = RE.PostId
        LIMIT 1
    )
WHERE
    RE.Rank <= 10
GROUP BY
    HU.UserId,
    HU.DisplayName,
    RE.PostId,
    RE.Title,
    RE.TotalEngagement
ORDER BY
    HU.DisplayName;