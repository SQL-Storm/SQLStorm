WITH TagExploded AS (
    SELECT
        P.Id AS PostId,
        CAST(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS INTEGER) AS TagId
    FROM Posts P
    WHERE P.PostTypeId = 1
),
BadgeStats AS (
    SELECT
        UserId,
        COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
),
HistoryStats AS (
    SELECT
        PostId,
        COUNT(*) AS HistoryCount
    FROM PostHistory
    GROUP BY PostId
),
RecentData AS (
    SELECT
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.Reputation AS AuthorReputation,
        COALESCE(BS.BadgeCount, 0) AS BadgeCount,
        COALESCE(HS.HistoryCount, 0) AS EditCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        STRING_AGG(DISTINCT T.TagName, ',') AS Tags
    FROM Posts P
    JOIN Users U ON U.Id = P.OwnerUserId
    LEFT JOIN BadgeStats BS ON BS.UserId = U.Id
    LEFT JOIN HistoryStats HS ON HS.PostId = P.Id
    LEFT JOIN Comments C ON C.PostId = P.Id
    LEFT JOIN Votes V ON V.PostId = P.Id
    LEFT JOIN TagExploded TE ON TE.PostId = P.Id
    LEFT JOIN Tags T ON T.Id = TE.TagId
    WHERE P.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
    GROUP BY
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.Reputation,
        BS.BadgeCount,
        HS.HistoryCount
)
SELECT
    RD.PostTypeId,
    COUNT(*) AS TotalPosts,
    AVG(RD.Score) AS AvgScore,
    AVG(RD.ViewCount) AS AvgViewCount,
    AVG(RD.AuthorReputation) AS AvgAuthorReputation,
    AVG(RD.BadgeCount) AS AvgBadges,
    AVG(RD.EditCount) AS AvgEdits,
    AVG(RD.CommentCount) AS AvgComments,
    AVG(RD.UpVotes) AS AvgUpVotes,
    AVG(RD.DownVotes) AS AvgDownVotes,
    STRING_AGG(DISTINCT RD.Tags, ',') AS DistinctTags
FROM RecentData RD
GROUP BY RD.PostTypeId
ORDER BY TotalPosts DESC;