-- {"query": "5076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1077} 
WITH ActiveUsers AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        MAX(P.CreationDate) AS LastPostDate
    FROM Users U
    LEFT JOIN Posts P ON P.OwnerUserId = U.Id
    WHERE U.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
    HAVING COUNT(P.Id) > 20
),
PostSummary AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.Title,
        COALESCE(P.AnswerCount,0) AS AnswerCount,
        (
            SELECT COUNT(*)
            FROM Comments C
            WHERE C.PostId = P.Id
        ) AS CommentCount,
        P.Tags,
        (
            SELECT array_to_string(ARRAY(
                SELECT REPLACE(tag,'>','') FROM unnest(string_to_array(substring(P.Tags,2,length(P.Tags)-2),'><')) AS tag
            ), ', ')
        ) AS TagList
    FROM Posts P
    INNER JOIN PostTypes PT ON PT.Id = P.PostTypeId
    WHERE P.CreationDate > NOW() - INTERVAL '18 months'
),
UserPostActivity AS (
    SELECT
        AU.UserId,
        AU.DisplayName,
        PS.PostId,
        PS.PostTypeName,
        PS.Score,
        PS.ViewCount,
        PS.CreationDate AS PostDate,
        PS.Title,
        PS.AnswerCount,
        PS.CommentCount,
        PS.TagList,
        DENSE_RANK() OVER (PARTITION BY AU.UserId ORDER BY PS.Score DESC, PS.ViewCount DESC) AS PostRank
    FROM ActiveUsers AU
    INNER JOIN PostSummary PS ON PS.OwnerUserId = AU.UserId
),
BadgeSummary AS (
    SELECT
        U.Id AS UserId,
        COUNT(*) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE B.Class = 3) AS BronzeBadges,
        COUNT(*) FILTER (WHERE B.TagBased = 1) AS TagBadges
    FROM Users U
    LEFT JOIN Badges B ON B.UserId = U.Id
    GROUP BY U.Id
),
RecentCloseReasons AS (
    SELECT
        PH.PostId,
        MAX(PH.CreationDate) AS LastClosedDate,
        CRT.Name AS CloseReason
    FROM PostHistory PH
    INNER JOIN CloseReasonTypes CRT 
        ON CRT.Id = 
            COALESCE(
                CASE WHEN PH.Comment ~ '^\d+$' THEN PH.Comment::smallint END,
                NULL
            )
    WHERE PH.PostHistoryTypeId = 10
      AND PH.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY PH.PostId, CRT.Name
)
SELECT
    UPA.UserId,
    UPA.DisplayName,
    AU.Reputation,
    AU.UpVotes,
    AU.DownVotes,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges,
    BS.TagBadges,
    UPA.PostId,
    UPA.PostTypeName,
    UPA.Title,
    COALESCE(UPA.AnswerCount, 0) AS AnswerCount,
    UPA.CommentCount,
    UPA.Score,
    UPA.ViewCount,
    UPA.TagList,
    UPA.PostDate,
    RC.LastClosedDate,
    RC.CloseReason,
    CASE
        WHEN UPA.TagList ILIKE '%sql%' THEN 'SQL Related'
        WHEN UPA.TagList ILIKE '%performance%' THEN 'Performance Related'
        WHEN UPA.TagList IS NULL THEN 'No Tags'
        ELSE 'Other'
    END AS PostCategory,
    CASE
        WHEN UPA.Score IS NULL THEN 'No Score'
        WHEN UPA.Score > 50 THEN 'Very High'
        WHEN UPA.Score > 10 THEN 'High'
        WHEN UPA.Score > 0 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreCategory
FROM UserPostActivity UPA
JOIN ActiveUsers AU ON UPA.UserId = AU.UserId
LEFT JOIN BadgeSummary BS ON BS.UserId = UPA.UserId
LEFT JOIN RecentCloseReasons RC ON RC.PostId = UPA.PostId
WHERE UPA.PostRank <= 3
  AND (
        UPA.TagList ILIKE '%sql%'
     OR UPA.PostTypeName = 'Question'
     OR UPA.Score > 20
     OR RC.CloseReason IS NOT NULL
  )
ORDER BY
    AU.Reputation DESC,
    UPA.Score DESC,
    UPA.ViewCount DESC,
    UPA.PostDate DESC
LIMIT 250;