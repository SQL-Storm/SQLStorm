-- {"query": "1523.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3156} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPostsOwned,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreOwned,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(COUNT(B.Id), 0) AS TotalBadgesEarned,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesGiven,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (3600 * 24) AS DaysActive,
        NULLIF(U.UpVotes + U.DownVotes, 0) AS TotalUserVotesProfile,
        (U.Reputation * 0.1 + COALESCE(COUNT(DISTINCT P.Id), 0) * 0.5 + COALESCE(COUNT(DISTINCT C.Id), 0) * 0.2 + COALESCE(COUNT(B.Id), 0) * 1) AS UserActivityScore
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId AND V.UserId IS NOT NULL
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostActivityLog AS (
    -- Set operator (UNION ALL) to combine different historical activities for posts
    SELECT PostId, CreationDate, 'CREATED_POST' AS ActivityType, OwnerUserId AS AffectedUserId FROM Posts WHERE PostTypeId IN (1,2)
    UNION ALL
    SELECT PostId, CreationDate, 'EDITED_POST' AS ActivityType, UserId AS AffectedUserId FROM PostHistory WHERE PostHistoryTypeId IN (4,5,6) AND UserId IS NOT NULL
    UNION ALL
    SELECT PostId, CreationDate, 'CLOSED_POST' AS ActivityType, UserId AS AffectedUserId FROM PostHistory WHERE PostHistoryTypeId = 10 AND UserId IS NOT NULL
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.Title,
        P.Body,
        P.Tags,
        P.AcceptedAnswerId,
        COALESCE(P.LastEditDate, P.CreationDate) AS EffectiveLastEditDate,
        -- Correlated subquery for average answer score
        (SELECT AVG(A.Score) FROM Posts A WHERE A.ParentId = P.Id AND A.PostTypeId = 2) AS AvgAnswerScoreForQuestion,
        -- Window function: RANK by score and views within each post type
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByScoreAndViews,
        -- Window function: LAG to get previous post score by the same owner
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScoreByOwner,
        COUNT(PL_Linked.RelatedPostId) AS LinkedPostsCount,
        COUNT(PL_Duplicate.RelatedPostId) AS DuplicatePostsCount,
        -- String expression and NULL logic for tag count
        COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'), 1), 0) AS NumberOfTags,
        -- Correlated subquery for times closed
        (
            SELECT SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
        ) AS TimesClosed,
        LOWER(SUBSTRING(P.Title, 1, 50)) AS LowerTitleExcerpt -- String function
    FROM Posts AS P
    LEFT JOIN PostLinks AS PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
    LEFT JOIN PostLinks AS PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.Title, P.Body, P.Tags, P.AcceptedAnswerId, P.LastEditDate
),
TagPerformance AS (
    -- Unnesting tags for individual tag analysis (PostgreSQL specific: UNNEST)
    SELECT
        UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS TagName,
        P.Id AS PostId,
        P.Score,
        P.ViewCount
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
AggregatedTagStats AS (
    SELECT
        TP.TagName,
        COUNT(TP.PostId) AS TagPostCount,
        AVG(TP.Score) AS AvgTagScore,
        AVG(TP.ViewCount) AS AvgTagViewCount,
        -- Window function: RANK tags by popularity
        RANK() OVER (ORDER BY COUNT(TP.PostId) DESC, AVG(TP.Score) DESC) AS TagPopularityRank
    FROM TagPerformance AS TP
    GROUP BY TP.TagName
)
SELECT
    COALESCE(UE.UserId, PD.OwnerUserId) AS FinalUserId,
    COALESCE(UE.DisplayName, U_Owner.DisplayName, 'Deleted User') AS UserDisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.LastAccessDate,
    UE.QuestionsPosted,
    UE.AnswersPosted,
    UE.TotalPostsOwned,
    UE.TotalPostScoreOwned,
    UE.TotalCommentsMade,
    UE.TotalBadgesEarned,
    UE.GoldBadges,
    UE.UpvotesGiven,
    UE.DownvotesGiven,
    UE.DaysActive,
    UE.TotalUserVotesProfile,
    UE.UserActivityScore,
    PD.PostId,
    PD.PostTypeId,
    PT.Name AS PostTypeName,
    PD.PostCreationDate,
    PD.Score AS PostScore,
    PD.ViewCount AS PostViewCount,
    PD.AnswerCount,
    PD.CommentCount AS PostCommentCount,
    PD.FavoriteCount AS PostFavoriteCount,
    PD.Title AS PostTitle,
    PD.LowerTitleExcerpt,
    PD.Tags AS PostTags,
    PD.NumberOfTags,
    PD.AvgAnswerScoreForQuestion,
    PD.RankByScoreAndViews AS PostRankByScoreAndViews,
    PD.PreviousPostScoreByOwner,
    PD.LinkedPostsCount,
    PD.DuplicatePostsCount,
    PD.TimesClosed,
    T.TagName AS PrimaryTagName, -- A sample tag for this post, from the LATERAL join
    ATS.TagPostCount,
    ATS.AvgTagScore,
    ATS.AvgTagViewCount,
    ATS.TagPopularityRank,
    -- Correlated subquery: comments by owner on a specific post
    (SELECT COUNT(*) FROM Comments C_sub WHERE C_sub.PostId = PD.PostId AND C_sub.UserId = UE.UserId) AS CommentsByOwnerOnPost,
    PH_LastEdit.CreationDate AS LastEditHistoryDate,
    PH_LastEdit.UserId AS LastEditorHistoryUserId,
    PH_LastEdit.Comment AS LastEditComment,
    -- Correlated subquery with CASE statement for user status
    (
        SELECT
            CASE
                WHEN EXISTS (SELECT 1 FROM Badges B_sub WHERE B_sub.UserId = COALESCE(UE.UserId, PD.OwnerUserId) AND B_sub.Name = 'Disciplined')
                THEN 'Disciplined User'
                ELSE 'Regular User'
            END
    ) AS UserDisciplineStatus,
    -- Complicated predicate/expression: CASE statement for question resolution
    CASE
        WHEN PD.PostTypeId = 1 AND PD.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
        WHEN PD.PostTypeId = 1 AND PD.AnswerCount > 0 AND PD.AcceptedAnswerId IS NULL THEN 'Unaccepted Answers'
        WHEN PD.PostTypeId = 1 AND PD.AnswerCount = 0 THEN 'No Answers'
        ELSE 'N/A'
    END AS QuestionResolutionStatus,
    LENGTH(PD.Body) AS PostBodyLength, -- String function
    NULLIF(UE.Reputation, 0) / NULLIF(UE.TotalPostsOwned, 0) AS ReputationPerPost, -- NULL logic for division by zero
    AGE(now(), PD.PostCreationDate) AS PostAge, -- Date calculation
    LOWER(REPLACE(PD.Title, ' ', '-')) AS SlugifiedTitle, -- String expression with REPLACE
    -- Subquery for total favorites
    (
        SELECT COUNT(DISTINCT V_sub.UserId)
        FROM Votes V_sub
        WHERE V_sub.PostId = PD.PostId AND V_sub.VoteTypeId = 5
    ) AS TotalFavoritesOnPost,
    -- String aggregation subquery with DISTINCT and LIMIT
    (
        SELECT STRING_AGG(TopVoters.DisplayName, ', ' ORDER BY TopVoters.DisplayName)
        FROM (
            SELECT DISTINCT U_voter.DisplayName
            FROM Votes V_sub
            JOIN Users U_voter ON V_sub.UserId = U_voter.Id
            WHERE V_sub.PostId = PD.PostId AND V_sub.VoteTypeId = 2
            ORDER BY U_voter.DisplayName
            LIMIT 5
        ) AS TopVoters
    ) AS Top5UpvotersDisplayNames,
    -- Integration of set operator CTE with a correlated subquery
    (
        SELECT COUNT(DISTINCT PAL_sub.ActivityType)
        FROM PostActivityLog PAL_sub
        WHERE PAL_sub.PostId = PD.PostId
    ) AS DistinctPostActivityTypesCount
FROM
    UserEngagement AS UE
FULL OUTER JOIN -- Full outer join to capture all users and all posts regardless of matching owner
    PostDetails AS PD ON UE.UserId = PD.OwnerUserId
LEFT JOIN
    PostTypes AS PT ON PD.PostTypeId = PT.Id
LEFT JOIN
    Users AS U_Owner ON PD.OwnerUserId = U_Owner.Id -- To get display name for posts if UE.UserId is NULL
LEFT JOIN LATERAL ( -- Lateral join to extract a single tag for joining, if available
    SELECT TagName FROM TagPerformance WHERE TagPerformance.PostId = PD.PostId LIMIT 1
) AS T ON TRUE
LEFT JOIN
    AggregatedTagStats AS ATS ON T.TagName = ATS.TagName
LEFT JOIN
    PostHistory AS PH_LastEdit ON PD.PostId = PH_LastEdit.PostId
    AND PH_LastEdit.CreationDate = (SELECT MAX(PH_sub.CreationDate) FROM PostHistory PH_sub WHERE PH_sub.PostId = PD.PostId AND PH_sub.PostHistoryTypeId IN (4, 5, 6)) -- Correlated subquery in join condition
WHERE
    -- Complicated predicate with multiple conditions and logical operators
    (UE.Reputation > 1000 OR PD.Score > 50 OR PD.ViewCount > 10000)
    AND (PD.PostTypeId = 1 OR PD.PostTypeId = 2)
    -- NULL logic and complex condition
    AND (UE.TotalBadgesEarned IS NULL OR UE.TotalBadgesEarned >= 2)
    AND PD.PostCreationDate > (NOW() - INTERVAL '5 year') -- Date comparison
    -- String pattern matching and NULL check
    AND (
        PD.Tags LIKE '%<sql>%' OR PD.Tags LIKE '%<database>%' OR PD.Tags IS NULL
    )
    -- NOT EXISTS correlated subquery for filtering spam comments
    AND NOT EXISTS (
        SELECT 1
        FROM Comments C_bad
        WHERE C_bad.PostId = PD.PostId
          AND C_bad.Text ILIKE '%spam%'
    )
    -- NULL logic and length check for post body
    AND (PD.Body IS NOT NULL AND LENGTH(PD.Body) > 100)
ORDER BY
    COALESCE(UE.UserActivityScore, 0) DESC, -- NULL handling in ORDER BY
    COALESCE(PD.RankByScoreAndViews, 999999) ASC,
    PD.EffectiveLastEditDate DESC
LIMIT 500;
