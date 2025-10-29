-- {"query": "1476.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2747} 

WITH UserEngagementSummary AS (
    -- Analyze user activity and reputation metrics, categorizing users by reputation quintile
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalFavoritesReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(U.LastAccessDate) AS LastActivityDate,
        DATE_PART('day', MAX(U.LastAccessDate) - MIN(U.CreationDate)) AS DaysActive,
        AVG(NULLIF(LENGTH(U.AboutMe), 0)) AS AvgAboutMeLength,
        NTILE(5) OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC) AS ReputationQuintile,
        RANK() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC, SUM(P.Score) DESC, U.CreationDate) AS PostActivityRank
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    WHERE U.Reputation > 5000 AND U.DisplayName IS NOT NULL AND U.Location IS NOT NULL
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.Views, U.CreationDate, U.AboutMe
    HAVING COUNT(DISTINCT P.Id) > 20 AND SUM(P.ViewCount) > 10000 -- Focus on highly active users
),
PostDetailsAndHistory AS (
    -- Enrich post data with type names, history counts, linked posts, and tag information
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.LastEditDate,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        LOWER(SUBSTRING(P.Title FROM 1 FOR 50)) AS TitlePrefixLower,
        AVG(V.BountyAmount) FILTER (WHERE V.VoteTypeId = 8) OVER (PARTITION BY P.Id) AS AvgBountyAmount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN 1 ELSE 0 END) AS EditHistoryCount, -- Edits or Suggested Edits Applied
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenHistoryCount,
        STRING_AGG(DISTINCT T.TagName, '; ') FILTER (WHERE T.TagName IS NOT NULL) AS AssociatedTagsString,
        (SELECT COUNT(DISTINCT PL.RelatedPostId)
         FROM PostLinks AS PL
         WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS LinkedPostsCount,
        (SELECT COUNT(DISTINCT PL.RelatedPostId)
         FROM PostLinks AS PL
         WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS DuplicatePostsCount,
        CASE
            WHEN P.ClosedDate IS NOT NULL AND PH_CLOSE.Comment IS NOT NULL THEN 'Closed: ' || COALESCE(CR.Name, 'Unknown Reason')
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered Accepted'
            WHEN P.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END AS PostStatusCategory,
        NULLIF(TRIM(REPLACE(REPLACE(REPLACE(P.Tags, '<sql>', ''), '<database>', ''), '<performance>', '')), '') AS RemainingTags
    FROM Posts AS P
    INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN PostHistory AS PH_CLOSE ON P.Id = PH_CLOSE.PostId AND PH_CLOSE.PostHistoryTypeId = 10 -- Specific join for close reason
    LEFT JOIN CloseReasonTypes AS CR ON CR.Id = NULLIF(PH_CLOSE.Comment, '')::smallint -- Convert comment to smallint for join
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    LEFT JOIN LATERAL (SELECT UNNEST(string_to_array(TRIM(P.Tags, '<>'), '><')) AS TagName) AS TagList ON TRUE
    LEFT JOIN Tags AS T ON TagList.TagName = T.TagName
    WHERE P.OwnerUserId IN (SELECT UserId FROM UserEngagementSummary WHERE ReputationQuintile <= 2)
      AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
      AND (P.ViewCount > 5000 OR P.Score > 100)
      AND P.PostTypeId IN (1, 2) -- Only questions and answers
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, PT.Name, P.Title, P.CreationDate, P.Score, P.ViewCount,
             P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastEditDate, P.ClosedDate, P.Body,
             PH_CLOSE.Comment, CR.Name, P.Tags
    ORDER BY P.Score DESC, P.ViewCount DESC
),
TagPerformance AS (
    -- Aggregate performance metrics for tags used in high-engagement posts
    SELECT
        Tag.TagName,
        COUNT(DISTINCT PD.PostId) AS TaggedPostCount,
        AVG(PD.PostScore) AS AvgPostScoreForTag,
        AVG(PD.PostViewCount) AS AvgPostViewCountForTag,
        SUM(PD.PostFavoriteCount) AS TotalFavoritesForTag,
        MAX(T.Count) AS GlobalTagUseCount,
        DENSE_RANK() OVER (ORDER BY AVG(PD.PostScore) DESC, COUNT(DISTINCT PD.PostId) DESC) AS TagScoreRank
    FROM PostDetailsAndHistory AS PD
    LEFT JOIN LATERAL (SELECT UNNEST(string_to_array(TRIM(Posts.Tags, '<>'), '><')) AS TagName FROM Posts WHERE Posts.Id = PD.PostId) AS Tag ON TRUE
    LEFT JOIN Tags AS T ON Tag.TagName = T.TagName
    WHERE Tag.TagName IS NOT NULL
    GROUP BY Tag.TagName, T.Count
    HAVING COUNT(DISTINCT PD.PostId) > 50 -- Consider only frequently used tags in this context
)
-- Final consolidated report combining user, post, and tag insights with complex derived metrics
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.ReputationQuintile,
    UES.PostActivityRank,
    UES.TotalPosts,
    UES.TotalPostScore,
    UES.TotalPostViews,
    UES.QuestionCount,
    UES.AnswerCount,
    UES.TotalCommentsMade,
    UES.AvgAboutMeLength,
    PDH.PostId,
    PDH.PostTypeName,
    PDH.Title,
    PDH.PostCreationDate,
    PDH.PostScore,
    PDH.PostViewCount,
    PDH.PostCommentCount,
    PDH.PostFavoriteCount,
    PDH.BodyLength,
    PDH.TitlePrefixLower,
    PDH.AvgBountyAmount,
    PDH.EditHistoryCount,
    PDH.CloseHistoryCount,
    PDH.ReopenHistoryCount,
    PDH.LinkedPostsCount,
    PDH.DuplicatePostsCount,
    PDH.PostStatusCategory,
    PDH.AssociatedTagsString,
    TP.TagName AS TopPerformingAssociatedTagName,
    TP.AvgPostScoreForTag AS TagAvgScore,
    TP.AvgPostViewCountForTag AS TagAvgViews,
    TP.TagScoreRank,
    (UES.TotalPostScore * 1.0 / NULLIF(UES.TotalPostViews, 0)) AS UserScorePerViewRatio,
    (PDH.PostScore * 1.0 / NULLIF(PDH.PostViewCount, 0)) AS IndividualPostScorePerView,
    (PDH.EditHistoryCount * 1.0 / NULLIF(DATE_PART('day', NOW() - PDH.PostCreationDate), 0)) AS EditsPerDaySinceCreation,
    (SELECT COUNT(DISTINCT B.Id) FROM Badges AS B WHERE B.UserId = UES.UserId AND B.Class = 1) AS GoldBadgeCount,
    COALESCE(UES.Location, 'Unknown') AS UserLocationStatus,
    CASE
        WHEN UES.AboutMe IS NULL OR LENGTH(TRIM(UES.AboutMe)) = 0 THEN 'No About Me'
        ELSE 'Has About Me'
    END AS AboutMeStatus,
    LAG(PDH.PostCreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY UES.UserId ORDER BY PDH.PostCreationDate) AS PreviousPostDate,
    LEAD(PDH.PostCreationDate, 1, '2999-12-31'::timestamp) OVER (PARTITION BY UES.UserId ORDER BY PDH.PostCreationDate) AS NextPostDate,
    (SELECT AVG(C.Score) FROM Comments AS C WHERE C.PostId = PDH.PostId AND C.CreationDate > PDH.PostCreationDate) AS AvgCommentScoreOnPost
FROM UserEngagementSummary AS UES
INNER JOIN PostDetailsAndHistory AS PDH ON UES.UserId = PDH.OwnerUserId
LEFT JOIN TagPerformance AS TP ON TP.TagName = (
    -- Correlated subquery to find the single highest-scoring associated tag for the current post
    SELECT TL_INNER.TagName
    FROM LATERAL (SELECT UNNEST(string_to_array(TRIM(Posts.Tags, '<>'), '><')) AS TagName FROM Posts WHERE Posts.Id = PDH.PostId) AS TL_INNER
    LEFT JOIN TagPerformance AS TP_INNER ON TP_INNER.TagName = TL_INNER.TagName
    WHERE TP_INNER.TagName IS NOT NULL
    ORDER BY TP_INNER.AvgPostScoreForTag DESC NULLS LAST, TP_INNER.TaggedPostCount DESC NULLS LAST
    LIMIT 1
)
WHERE UES.ReputationQuintile = 1 AND PDH.PostScore > 50 AND PDH.EditHistoryCount > 0
  AND (PDH.Title LIKE '%performance%' OR PDH.Title LIKE '%optimization%' OR PDH.AssociatedTagsString LIKE '%<sql>%')
  AND (UES.TotalPosts > 200 OR UES.TotalFavoritesReceived > 1000)
  AND (PDH.ClosedDate IS NULL OR PDH.PostStatusCategory LIKE 'Closed: Duplicate%')
  AND (PDH.RemainingTags IS NOT NULL AND LENGTH(PDH.RemainingTags) > 5)
ORDER BY UES.Reputation DESC, PDH.PostScore DESC, GoldBadgeCount DESC, EditsPerDaySinceCreation DESC;
