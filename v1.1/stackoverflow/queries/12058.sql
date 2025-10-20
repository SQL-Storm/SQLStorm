WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.Title,
        P.Tags,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY P.Id) AS UpVotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) OVER (PARTITION BY P.Id) AS DownVotes,
        COUNT(C.Id) OVER (PARTITION BY P.Id) AS CommentCount,
        P.OwnerUserId
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
),
TopPosts AS (
    SELECT 
        *
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 10
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore,
        SUM(P.ViewCount) AS TotalViews
    FROM 
        Tags T
    JOIN 
        Posts P ON (
            EXISTS (
                SELECT 1
                FROM (
                    SELECT regexp_split_to_table(
                        CASE
                            WHEN left(P.Tags,1) = '<' AND right(P.Tags,1) = '>' THEN substring(P.Tags FROM 2 FOR (LENGTH(P.Tags)-2))
                            ELSE P.Tags
                        END,
                        '><'
                    ) AS t
                ) s
                WHERE s.t = T.TagName
            )
        )
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(P.Id) AS PostCount,
        COALESCE(SUM(P.Score), 0) AS TotalScore,
        COUNT(B.Id) AS BadgeCount,
        MAX(P.LastActivityDate) AS LastActivity
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) AS RevisionCount,
        MAX(PH.CreationDate) AS LastRevisionDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
MergedPostStats AS (
    SELECT 
        P1.Id AS PostId,
        P1.Title AS PostTitle,
        P2.Id AS RelatedPostId,
        P2.Title AS RelatedPostTitle,
        PL.LinkTypeId,
        PH1.RevisionCount AS PostRevisionCount,
        PH2.RevisionCount AS RelatedPostRevisionCount
    FROM 
        Posts P1
    JOIN 
        PostLinks PL ON P1.Id = PL.PostId
    JOIN 
        Posts P2 ON PL.RelatedPostId = P2.Id
    LEFT JOIN 
        PostHistorySummary PH1 ON P1.Id = PH1.PostId
    LEFT JOIN 
        PostHistorySummary PH2 ON P2.Id = PH2.PostId
    WHERE 
        PL.LinkTypeId = 3
)
SELECT 
    TOP.Id,
    TOP.PostTypeId,
    TOP.Score,
    TOP.ViewCount,
    TOP.CreationDate,
    TOP.Title,
    TOP.Tags,
    TOP.OwnerDisplayName,
    TOP.PostRank,
    TOP.UpVotes,
    TOP.DownVotes,
    TOP.CommentCount,
    TS.TagName,
    TS.PostCount AS TagPostCount,
    TS.AvgScore AS TagAvgScore,
    TS.TotalViews AS TagTotalViews,
    UA.DisplayName AS UserDisplayName,
    UA.PostCount AS UserPostCount,
    UA.TotalScore AS UserTotalScore,
    UA.BadgeCount AS UserBadgeCount,
    UA.LastActivity AS UserLastActivity,
    MPS.RelatedPostId,
    MPS.RelatedPostTitle,
    MPS.LinkTypeId,
    MPS.PostRevisionCount,
    MPS.RelatedPostRevisionCount
FROM 
    TopPosts TOP
JOIN 
    TagStats TS ON TS.TagName IN (
        SELECT t FROM (
            SELECT regexp_split_to_table(
                CASE
                    WHEN left(TOP.Tags,1) = '<' AND right(TOP.Tags,1) = '>' THEN substring(TOP.Tags FROM 2 FOR (LENGTH(TOP.Tags)-2))
                    ELSE TOP.Tags
                END,
                '><'
            ) AS t
        ) s
    )
LEFT JOIN 
    UserActivity UA ON TOP.OwnerUserId = UA.Id
LEFT JOIN 
    MergedPostStats MPS ON TOP.Id = MPS.PostId
ORDER BY 
    TOP.Score DESC, 
    TOP.CreationDate;