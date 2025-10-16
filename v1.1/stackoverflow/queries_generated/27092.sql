-- {"query": "27092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1503} 

WITH RankedUsers AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY U.UpVotes DESC) AS UpVotesRank,
        NTILE(10) OVER (ORDER BY U.DownVotes DESC) AS DownVotesDecile
    FROM
        Users U
),
ActivePosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        EXTRACT(YEAR FROM P.CreationDate) AS Year,
        CASE
            WHEN P.PostTypeId = 1 THEN 'Question'
            WHEN P.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeName,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        COALESCE(LAG(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate), 0) AS PreviousScore,
        LEAD(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextScore
    FROM
        Posts P
    LEFT JOIN
        RankedUsers U ON P.OwnerUserId = U.UserId
    WHERE
        P.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
TagAnalysis AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        STRING_AGG(DISTINCT P.Title, ', ') AS PopularTitles,
        CASE
            WHEN T.Count > 1000 THEN 'High'
            WHEN T.Count BETWEEN 500 AND 1000 THEN 'Medium'
            ELSE 'Low'
        END AS TagPopularity
    FROM
        Tags T
    LEFT JOIN
        ActivePosts P ON P.Tags LIKE '%< ' || T.TagName || '>%'
    GROUP BY
        T.Id, T.TagName, T.Count
    ORDER BY
        PostCount DESC
),
VoteDistribution AS (
    SELECT
        V.PostId,
        V.VoteTypeId,
        U.DisplayName AS VoterDisplayName,
        V.CreationDate AS VoteDate,
        V.BountyAmount,
        LAG(V.VoteTypeId, 1) OVER (PARTITION BY V.PostId ORDER BY V.CreationDate) AS PreviousVoteType,
        NTILE(5) OVER (PARTITION BY V.PostId ORDER BY V.CreationDate) AS VoteQuintile
    FROM
        Votes V
    LEFT JOIN
        Users U ON V.UserId = U.Id
),
BadgeSummary AS (
    SELECT
        B.UserId,
        U.DisplayName,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(DISTINCT B.Name, ', ') AS BadgeNames
    FROM
        Badges B
    LEFT JOIN
        Users U ON B.UserId = U.Id
    GROUP BY
        B.UserId, U.DisplayName
)
SELECT
    A.PostId,
    A.PostTypeName,
    A.Title,
    A.OwnerDisplayName,
    A.Score,
    A.ViewCount,
    T.TagName,
    T.TagPopularity,
    V.VoteTypeId,
    V.VoterDisplayName,
    V.VoteDate,
    BS.TotalBadges,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges,
    (A.Score - A.PreviousScore) AS ScoreChange,
    CASE
        WHEN A.Score > A.PreviousScore THEN 'Increased'
        WHEN A.Score < A.PreviousScore THEN 'Decreased'
        ELSE 'Unchanged'
    END AS ScoreTrend,
    COALESCE(A.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    CASE
        WHEN V.VoteTypeId = 2 THEN 'Upvote'
        WHEN V.VoteTypeId = 3 THEN 'Downvote'
        ELSE 'Other'
    END AS VoteTypeName,
    V.VoteQuintile,
    CASE
        WHEN V.PreviousVoteType IS NULL THEN 'First Vote'
        WHEN V.PreviousVoteType = V.VoteTypeId THEN 'Consistent Vote'
        ELSE 'Changed Vote'
    END AS VotePattern
FROM
    ActivePosts A
LEFT JOIN
    TagAnalysis T ON A.Tags LIKE '%< ' || T.TagName || '>%'
FULL OUTER JOIN
    VoteDistribution V ON A.PostId = V.PostId
LEFT JOIN
    BadgeSummary BS ON A.OwnerUserId = BS.UserId
WHERE
    A.ViewCount > 1000 AND
    A.Score > 10 AND
    T.PostCount IS NOT NULL
ORDER BY
    A.Score DESC,
    T.PostCount DESC;
