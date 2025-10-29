-- {"query": "2555.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1483} 

WITH RecursiveUserBadgeCounts AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        B.Class,
        COUNT(B.Id) AS BadgeCount
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, B.Class

    UNION ALL

    SELECT
        r.UserId,
        r.DisplayName,
        r.Class,
        r.BadgeCount
    FROM RecursiveUserBadgeCounts r
    WHERE r.BadgeCount > 0
),
TopBadges AS (
    SELECT
        UserId,
        MAX(BadgeCount) AS MaxBadgeCount
    FROM RecursiveUserBadgeCounts
    GROUP BY UserId
),
RecentPostsWithActivity AS (
    SELECT
        P.Id,
        P.PostTypeId,
        P.Title,
        P.Tags,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS rn,
        COALESCE(P.FavoriteCount, 0) + COALESCE(P.CommentCount, 0) AS EngagementScore,
        P.ClosedDate,
        L.LinkTypeId,
        LT.Name AS LinkTypeName,
        PT.Name AS PostTypeName,
        U.DisplayName AS OwnerDisplayName,
        CASE WHEN P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts P
    LEFT JOIN PostLinks L ON L.PostId = P.Id
    LEFT JOIN LinkTypes LT ON LT.Id = L.LinkTypeId
    LEFT JOIN PostTypes PT ON PT.Id = P.PostTypeId
    LEFT JOIN Users U ON U.Id = P.OwnerUserId
    WHERE P.CreationDate >= NOW() - INTERVAL '180 days'
),
LikedComments AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS CommentCount,
        SUM(C.Score) AS TotalCommentScore,
        STRING_AGG(C.Text, ' | ' ORDER BY C.CreationDate DESC) AS ConcatenatedComments
    FROM Comments C
    WHERE C.Score > 0
    GROUP BY C.PostId
),
UserPostVotesWindowed AS (
    SELECT
        V.PostId,
        V.UserId,
        COUNT(*) AS UserVotesCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY V.UserId ORDER BY MAX(V.CreationDate) DESC) AS RecentVoteRank
    FROM Votes V
    GROUP BY V.PostId, V.UserId
),
FilteredPosts AS (
    SELECT
        RPA.Id,
        RPA.PostTypeId,
        RPA.Title,
        RPA.Tags,
        RPA.CreationDate,
        RPA.Score,
        RPA.ViewCount,
        RPA.OwnerUserId,
        RPA.AcceptedAnswerId,
        RPA.EngagementScore,
        RPA.IsClosed,
        RPA.LinkTypeId,
        RPA.LinkTypeName,
        RPA.PostTypeName,
        RPA.OwnerDisplayName,
        COALESCE(LC.CommentCount, 0) AS CommentCount,
        COALESCE(LC.TotalCommentScore, 0) AS TotalCommentScore,
        LC.ConcatenatedComments
    FROM RecentPostsWithActivity RPA
    LEFT JOIN LikedComments LC ON LC.PostId = RPA.Id
    WHERE RPA.rn <= 5
      AND (RPA.ClosedDate IS NULL OR RPA.ClosedDate > NOW() - INTERVAL '30 days')
      AND RPA.Score >= (
          SELECT COALESCE(AVG(Score), 0) FROM Posts WHERE PostTypeId = RPA.PostTypeId AND CreationDate >= NOW() - INTERVAL '180 days'
      )
),
DetailedPostStats AS (
    SELECT
        FP.*,
        (SELECT COUNT(*) FROM PostLinks PL WHERE PL.RelatedPostId = FP.Id AND PL.LinkTypeId = 3) AS NumDuplicates,
        (SELECT COUNT(*) FROM Votes V WHERE V.PostId = FP.Id AND V.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(*) FROM Votes V WHERE V.PostId = FP.Id AND V.VoteTypeId = 3) AS DownvoteCount,
        EXISTS (
            SELECT 1 FROM PostHistory PH
            WHERE PH.PostId = FP.Id AND PH.PostHistoryTypeId IN (10, 11)
              AND PH.CreationDate > FP.CreationDate
        ) AS HasCloseReopenEvents,
        (
            SELECT AVG(Score)
            FROM Posts P2
            WHERE POSITION(',' || P2.Tags || ',' IN ',' || REPLACE(FP.Tags, '><', ',') || ',') > 0
            AND P2.PostTypeId = FP.PostTypeId
        ) AS AvgScoreForSharedTags
    FROM FilteredPosts FP
)
SELECT
    DPS.Id AS PostId,
    DPS.PostTypeName,
    DPS.Title,
    DPS.OwnerDisplayName,
    DPS.CreationDate,
    DPS.Score,
    DPS.ViewCount,
    DPS.EngagementScore,
    DPS.CommentCount,
    DPS.TotalCommentScore,
    DPS.NumDuplicates,
    DPS.UpvoteCount,
    DPS.DownvoteCount,
    DPS.IsClosed,
    DPS.HasCloseReopenEvents,
    DPS.AvgScoreForSharedTags,
    CASE
        WHEN DPS.Score > DPS.AvgScoreForSharedTags THEN 'Above Average'
        WHEN DPS.Score = DPS.AvgScoreForSharedTags THEN 'Average'
        ELSE 'Below Average'
    END AS ScoreComparisonToTagAvg,
    DPS.ConcatenatedComments,
    CONCAT('Tags: ', COALESCE(DPS.Tags, 'None')) AS TagInfo
FROM DetailedPostStats DPS
ORDER BY DPS.EngagementScore DESC, DPS.Score DESC, DPS.ViewCount DESC
LIMIT 25

UNION

SELECT
    NULL AS PostId,
    'Summary' AS PostTypeName,
    NULL AS Title,
    NULL AS OwnerDisplayName,
    NULL AS CreationDate,
    AVG(Score)::INT AS Score,
    AVG(ViewCount)::INT AS ViewCount,
    SUM(EngagementScore) AS EngagementScore,
    SUM(CommentCount) AS CommentCount,
    SUM(TotalCommentScore) AS TotalCommentScore,
    SUM(NumDuplicates) AS NumDuplicates,
    SUM(UpvoteCount) AS UpvoteCount,
    SUM(DownvoteCount) AS DownvoteCount,
    NULL AS IsClosed,
    NULL AS HasCloseReopenEvents,
    NULL AS AvgScoreForSharedTags,
    NULL AS ScoreComparisonToTagAvg,
    NULL AS ConcatenatedComments,
    NULL AS TagInfo
FROM DetailedPostStats
WHERE PostTypeName IN ('Question', 'Answer')
;
