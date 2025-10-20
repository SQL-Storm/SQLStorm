-- {"query": "49094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2824} 
WITH TaggedContent AS (
    -- Identify posts (questions and answers) containing the 'sql' tag within a specific active period
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS UserId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ParentId
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate >= '2022-01-01' -- Define an active period start date
      AND (P.PostTypeId = 1 OR P.PostTypeId = 2) -- Only consider Questions (1) and Answers (2)
      AND EXISTS (
            -- Efficiently check for the 'sql' tag using UNNEST and string_to_array
            SELECT 1
            FROM UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS tag_name
            WHERE tag_name = 'sql'
      )
),
TaggedPostsWithAcceptedStatus AS (
    -- Augment TaggedContent with information about whether an answer was accepted by its parent question
    SELECT
        TC.PostId,
        TC.UserId,
        TC.PostTypeId,
        TC.CreationDate,
        TC.Score,
        TC.ViewCount,
        TC.AnswerCount,
        TC.CommentCount,
        TC.FavoriteCount,
        TC.ParentId,
        CASE
            WHEN TC.PostTypeId = 2 AND QP.AcceptedAnswerId = TC.PostId THEN TRUE
            ELSE FALSE
        END AS IsAcceptedAnswer
    FROM TaggedContent TC
    LEFT JOIN Posts QP ON TC.ParentId = QP.Id AND TC.PostTypeId = 2 -- Join to get the parent question's accepted answer
),
UserTagActivitySummary AS (
    -- Aggregate various metrics for each user based on their activity within the 'sql' tag
    SELECT
        TPA.UserId,
        COUNT(DISTINCT TPA.PostId) AS TotalPostsInTag,
        COUNT(DISTINCT CASE WHEN TPA.PostTypeId = 1 THEN TPA.PostId END) AS QuestionsAskedInTag,
        COUNT(DISTINCT CASE WHEN TPA.PostTypeId = 2 THEN TPA.PostId END) AS AnswersGivenInTag,
        SUM(CASE WHEN TPA.IsAcceptedAnswer THEN 1 ELSE 0 END) AS AcceptedAnswersInTag,
        SUM(TPA.Score) AS TotalPostScoreInTag,
        SUM(TPA.ViewCount) AS TotalViewCountInTag,
        SUM(TPA.CommentCount) AS TotalCommentsOnPostsInTag,
        SUM(TPA.FavoriteCount) AS TotalFavoriteCountInTag,
        MAX(TPA.CreationDate) AS LastActivityDateInTag,
        MIN(TPA.CreationDate) AS FirstActivityDateInTag,
        -- Calculate the duration of activity in days
        EXTRACT(EPOCH FROM (MAX(TPA.CreationDate) - MIN(TPA.CreationDate))) / (60 * 60 * 24) AS DaysActiveInTag
    FROM TaggedPostsWithAcceptedStatus TPA
    GROUP BY TPA.UserId
),
UserCommentContributions AS (
    -- Summarize the total number of comments made by each user within the active period
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalCommentsMadeByAuthor
    FROM Comments C
    WHERE C.CreationDate >= '2022-01-01'
      AND C.UserId IS NOT NULL
    GROUP BY C.UserId
),
UserBadgeSummary AS (
    -- Count 'sql' tag-specific badges (Gold, Silver, Bronze) for each user
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgesForTag,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadgesForTag,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadgesForTag,
        COUNT(B.Id) AS TotalTagBadges
    FROM Badges B
    WHERE B.TagBased = TRUE -- Ensure it's a tag-based badge
      AND B.Name = 'sql'
    GROUP BY B.UserId
),
UserEditActivity AS (
    -- Count significant post edits made by users on 'sql' tagged posts within the active period
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalEditsOnTaggedPosts
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
      AND PH.CreationDate >= '2022-01-01'
      AND PH.UserId IS NOT NULL
      AND PH.PostId IN (SELECT PostId FROM TaggedContent) -- Only consider edits on 'sql' tagged posts
    GROUP BY PH.UserId
),
UserVoteCounts AS (
    -- Count the different types of votes cast by users on 'sql' tagged posts within the active period
    SELECT
        V.UserId,
        COUNT(CASE WHEN VT.Name = 'UpMod' THEN 1 END) AS UpVotesCast,
        COUNT(CASE WHEN VT.Name = 'DownMod' THEN 1 END) AS DownVotesCast,
        COUNT(CASE WHEN VT.Name = 'Favorite' THEN 1 END) AS FavoritesMade,
        COUNT(CASE WHEN VT.Name = 'AcceptedByOriginator' THEN 1 END) AS AcceptedVotesGiven
    FROM Votes V
    JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
    WHERE V.CreationDate >= '2022-01-01'
      AND V.UserId IS NOT NULL
      AND V.PostId IN (SELECT PostId FROM TaggedContent)
    GROUP BY V.UserId
),
UserClosureVotes AS (
    -- Count the number of close votes cast by users on 'sql' tagged posts
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalCloseVotesCast,
        COUNT(CASE WHEN PH.Comment = '101' THEN 1 END) AS DuplicateCloseVotes -- Assuming '101' is a duplicate close reason
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId = 10 -- Post Closed
      AND PH.CreationDate >= '2022-01-01'
      AND PH.UserId IS NOT NULL
      AND PH.PostId IN (SELECT PostId FROM TaggedContent)
    GROUP BY PH.UserId
)
-- Main query: Combine all user activity summaries and rank users based on a composite activity score
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation AS CurrentReputation,
    U.CreationDate AS UserCreationDate,
    COALESCE(UTAS.TotalPostsInTag, 0) AS TotalPostsInTag,
    COALESCE(UTAS.QuestionsAskedInTag, 0) AS QuestionsAskedInTag,
    COALESCE(UTAS.AnswersGivenInTag, 0) AS AnswersGivenInTag,
    COALESCE(UTAS.AcceptedAnswersInTag, 0) AS AcceptedAnswersInTag,
    COALESCE(UTAS.TotalPostScoreInTag, 0) AS TotalPostScoreInTag,
    COALESCE(UTAS.TotalViewCountInTag, 0) AS TotalViewCountInTag,
    COALESCE(UTAS.TotalCommentsOnPostsInTag, 0) AS TotalCommentsOnPostsInTag,
    COALESCE(UCC.TotalCommentsMadeByAuthor, 0) AS TotalCommentsMadeByAuthor,
    COALESCE(UTAS.TotalFavoriteCountInTag, 0) AS TotalFavoriteCountInTag,
    COALESCE(UBS.GoldBadgesForTag, 0) AS GoldBadgesForTag,
    COALESCE(UBS.SilverBadgesForTag, 0) AS SilverBadgesForTag,
    COALESCE(UBS.BronzeBadgesForTag, 0) AS BronzeBadgesForTag,
    COALESCE(UBS.TotalTagBadges, 0) AS TotalTagBadges,
    COALESCE(UEA.TotalEditsOnTaggedPosts, 0) AS TotalEditsOnTaggedPosts,
    COALESCE(UVC.UpVotesCast, 0) AS UpVotesCastByAuthor,
    COALESCE(UVC.DownVotesCast, 0) AS DownVotesCastByAuthor,
    COALESCE(UVC.FavoritesMade, 0) AS FavoritesMadeByAuthor,
    COALESCE(UVC.AcceptedVotesGiven, 0) AS AcceptedVotesGivenByAuthor,
    COALESCE(UCV.TotalCloseVotesCast, 0) AS TotalCloseVotesCastByAuthor,
    COALESCE(UCV.DuplicateCloseVotes, 0) AS DuplicateCloseVotesByAuthor,
    UTAS.FirstActivityDateInTag,
    UTAS.LastActivityDateInTag,
    UTAS.DaysActiveInTag,
    -- Calculate a weighted composite activity score for ranking
    (
        COALESCE(UTAS.TotalPostScoreInTag, 0) * 1.0 +
        COALESCE(UTAS.AcceptedAnswersInTag, 0) * 10.0 +
        COALESCE(UTAS.QuestionsAskedInTag, 0) * 2.0 +
        COALESCE(UTAS.AnswersGivenInTag, 0) * 5.0 +
        COALESCE(UCC.TotalCommentsMadeByAuthor, 0) * 0.5 +
        COALESCE(UBS.GoldBadgesForTag, 0) * 25.0 +
        COALESCE(UBS.SilverBadgesForTag, 0) * 10.0 +
        COALESCE(UBS.BronzeBadgesForTag, 0) * 2.0 +
        COALESCE(UEA.TotalEditsOnTaggedPosts, 0) * 1.0 +
        COALESCE(UCV.TotalCloseVotesCast, 0) * (-2.0) -- Penalize close votes to some extent
    ) AS CompositeActivityScore,
    -- Rank users based on the composite score, breaking ties with current reputation
    RANK() OVER (ORDER BY (
        COALESCE(UTAS.TotalPostScoreInTag, 0) * 1.0 +
        COALESCE(UTAS.AcceptedAnswersInTag, 0) * 10.0 +
        COALESCE(UTAS.QuestionsAskedInTag, 0) * 2.0 +
        COALESCE(UTAS.AnswersGivenInTag, 0) * 5.0 +
        COALESCE(UCC.TotalCommentsMadeByAuthor, 0) * 0.5 +
        COALESCE(UBS.GoldBadgesForTag, 0) * 25.0 +
        COALESCE(UBS.SilverBadgesForTag, 0) * 10.0 +
        COALESCE(UBS.BronzeBadgesForTag, 0) * 2.0 +
        COALESCE(UEA.TotalEditsOnTaggedPosts, 0) * 1.0 +
        COALESCE(UCV.TotalCloseVotesCast, 0) * (-2.0)
    ) DESC, U.Reputation DESC) AS RankByActivity
FROM Users U
LEFT JOIN UserTagActivitySummary UTAS ON U.Id = UTAS.UserId
LEFT JOIN UserCommentContributions UCC ON U.Id = UCC.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN UserEditActivity UEA ON U.Id = UEA.UserId
LEFT JOIN UserVoteCounts UVC ON U.Id = UVC.UserId
LEFT JOIN UserClosureVotes UCV ON U.Id = UCV.UserId
-- Filter to include only users who have some form of relevant activity within the period
WHERE (UTAS.UserId IS NOT NULL OR UCC.UserId IS NOT NULL OR UBS.UserId IS NOT NULL OR UEA.UserId IS NOT NULL OR UVC.UserId IS NOT NULL OR UCV.UserId IS NOT NULL)
ORDER BY RankByActivity
LIMIT 100;