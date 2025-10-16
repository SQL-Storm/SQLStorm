-- {"query": "27087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1697} 

WITH ActiveUsers AS (
    SELECT
        UserId,
        Reputation,
        LastAccessDate,
        UpVotes,
        DownVotes,
        Views,
        COALESCE(AboutMe, '') AS AboutMe,
        COALESCE(ProfileImageUrl, '') AS ProfileImageUrl,
        COALESCE(WebsiteUrl, '') AS WebsiteUrl,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, LastAccessDate DESC) AS rank
    FROM
        Users
    WHERE
        Reputation > 1000 AND
        LastAccessDate >= DATEADD(month, -1, GETDATE())
),
TopPosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.Title,
        P.Body,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        PT.Name AS PostTypeName,
        COALESCE(P.LastEditorUserId,-1) AS LastEditorUserId,
        P.LastEditDate,
        COALESCE(P.LastEditorDisplayName,'') AS LastEditorDisplayName,
        P.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS post_rank
    FROM
        Posts P
    JOIN
         PostTypes PT ON P.PostTypeId = PT.Id
    WHERE
        P.PostTypeId IN (1, 2) AND
        P.Score >= 10 AND
        P.CreationDate >= DATEADD(year, -1, GETDATE())
),
BadgesInfo AS (
    SELECT
        U.UserId,
        B.Name AS BadgeName,
        B.Class,
        B.Date,
        COUNT(B.Id) OVER (PARTITION BY U.UserId, B.Class) AS BadgeCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) OVER
        (PARTITION BY U.UserId) AS GoldBadges,
        SUM(CASE WHEN B.Class = 1
           THEN 3 ELSE CASE WHEN B.Class = 2
           THEN 2 ELSE 1 END END) OVER
           (PARTITION BY U.UserId) AS BadgeScore
    FROM
        Users U
    JOIN
        Badges B ON U.Id = B.UserId
      WHERE
        B.Date >= DATEADD(month, -6, GETDATE())
)
 SELECT
    U.UserId,
    U.DisplayName,
    U.Reputation,
    U.LastAccessDate,
    U.AboutMe,
    U.ProfileImageUrl,
    U.WebsiteUrl,
    U.Views,
    U.UpVotes,
    U.DownVotes,
    TP.PostId,
    TP.PostTypeName,
    TP.Title,
    TP.Score AS PostScore,
    TP.ViewCount,
    TP.AnswerCount,
    TP.CommentCount,
    TP.Body,
    TP.LastActivityDate,
    TP.LastEditorUserId,
    TP.LastEditorDisplayName,
    TP.post_rank,
    BI.BadgeName,
    BI.Class,
    BI.BadgeCount,
    BI.GoldBadges,
    BI.BadgeScore,
    COALESCE(V.PostId, -1) AS VotedPostId,
    COALESCE(V.VoteTypeId, -1) AS VoteTypeId,
    CASE
        WHEN V.VoteTypeId IS NOT NULL THEN VT.Name
        ELSE 'No Votes'
    END AS VoteTypeName,
    V.CreationDate AS VoteCreationDate,
    LEN(TP.Body) - LEN(REPLACE(TP.Body, ' ', '')) + 1 AS WordCount,
    CASE
        WHEN CHARINDEX('<a ', TP.Body) > 0 THEN 'Contains Links'
        ELSE 'No Links'
    END AS LinkStatus,
    TT.TagName,
    T.Count,
    Substring(SUBSTRING(P.Tags, 2, LEN(P.Tags) - 2), 0, CHARINDEX( '><', SUBSTRING(P.Tags, 2, LEN(P.Tags) - 2))) as FirstTagName
FROM
    ActiveUsers U
LEFT JOIN
    TopPosts TP ON U.UserId = TP.OwnerUserId AND TP.PostTypeId = 1
 AND ((CASE WHEN TP.Body LIKE '%<a %' THEN 'Yes' ELSE 'No' END) = 'No')
 LEFT JOIN (Select * from ( TABLE VALUE CONVERTERS ( SUBSTRING('><'+Tags+'><', 2 , LEN( '><'+Tags+'><'  )-2)  ) )AS VARCHAR(4000) ) ) as popularTags on popularTags.value=Substring(SUBSTRING(TP.Tags, 2, LEN(TP.Tags) - 2), 0, CHARINDEX( '><', SUBSTRING(TP.Tags, 2, LEN(TP.Tags) - 2))) AS SubsequenceFromTag
LEFT JOIN
    Votes V ON TP.PostId = V.PostId
LEFT JOIN
    VoteTypes VT ON V.VoteTypeId = VT.Id
LEFT JOIN
    Tags T ON T.Id = TP.POSTID
LEFT JOIN
    Tags TT ON
    TP.OwnerUserId=TT.Id
 LEFT JOIN(
        SELECT PL.PostId,CAST(PL.RelatedPostId as varchar(600)) as spamPost_info , LT.Name, COALESCE(Pl.Id ,0) as relativePostID,
        ROW_NUMBER() OVER (PARTITION BY RelatedPostId ORDER BY PL.Id DESC) AS related_info_rank
       FROM
       PostLinks PL
       JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
        WHERE
        RelatedPostId IS NOT NULL) PL ON TP.PostID= PL.POSTID
LEFT JOIN BadgesInfo BI ON U.UserId = BI.UserId
LEFT JOIN
    PostHistory PH ON TP.PostId = PH.PostId
    WHERE (PH.UserId = U.UserId AND
        (PH.PostHistoryTypeId = 10 OR PH.PostHistoryTypeId = 14
        OR PH.PostHistoryTypeId = 66)
     WHERE((TP.AnswerCount > 5) AND (TP.CommentCount/TP.Score)>0.5 AND (TP.Score>=5))  AND ( WordCount > 200 )
     ORDER BY PostSCORE)}))  ORDER BY U.Reputation desc, PostRank desc `{}
